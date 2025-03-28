package cluster

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/distribution/reference"
	"github.com/google/uuid"
	"github.com/replicatedhq/kurl/pkg/k8sutil"
	"golang.org/x/sync/errgroup"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/utils/ptr"
	"k8s.io/utils/strings/slices"
)

const (
	// DefaultNodeImagesJobImage is the default image to use for the node images job
	// This image must have the docker CLI on the path
	DefaultNodeImagesJobImage = "docker.io/replicated/kurl-util:latest"
	// DefaultNodeImagesJobNamespace is the default namespace to use for the node images job
	DefaultNodeImagesJobNamespace = "kurl"
	// DefaultNodeImagesJobTimeout is the default timeout for the node images job
	// This timeout must be greater than 0
	DefaultNodeImagesJobTimeout = 120 * time.Second
)

// NodeImagesJobOptions are options for the node images job
type NodeImagesJobOptions struct {
	JobNamespace string
	JobImage     string
	Timeout      time.Duration
	TargetNode   string
	ExcludeNodes []string

	nodeImagesJobRunner nodeImagesJobRunner
}

// nodeImagesJobRunner is used for testing
type nodeImagesJobRunner func(context.Context, kubernetes.Interface, *log.Logger, corev1.Node, NodeImagesJobOptions) ([]corev1.ContainerImage, error)

// NodeImages returns a map of node names to maps of images present on that node.
// It will use node.Status.Images if it is likely comprehensive, otherwise it will fallback to run
// a job on all nodes if not.
func NodeImages(ctx context.Context, client kubernetes.Interface, logger *log.Logger, opts NodeImagesJobOptions) (map[string]map[string]struct{}, error) {
	nodes, err := client.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("unable to list nodes: %w", err)
	}

	nodeImages := map[string]map[string]struct{}{}

	g := errgroup.Group{}

	if opts.nodeImagesJobRunner == nil {
		opts.nodeImagesJobRunner = runNodeImagesJob
	}

	for _, n := range nodes.Items {
		node := n
		if opts.TargetNode != "" && node.Name != opts.TargetNode {
			continue
		}
		if slices.Contains(opts.ExcludeNodes, node.Name) {
			continue
		}
		thisNodeImages := map[string]struct{}{}
		for _, image := range node.Status.Images {
			for _, name := range image.Names {
				ref, _ := reference.ParseDockerRef(name)
				if ref != nil {
					name = ref.String()
				}
				thisNodeImages[name] = struct{}{}
			}
		}
		nodeImages[node.Name] = thisNodeImages
		// 50 is the default value for max images per node. If the length is equal it is likely
		// that the node has more than 50 images.
		if len(node.Status.Images) == 0 || len(node.Status.Images) == 50 {
			g.Go(func() error {
				images, err := opts.nodeImagesJobRunner(ctx, client, logger, node, opts)
				if err != nil {
					return fmt.Errorf("failed to run job on node %s: %w", node.Name, err)
				}
				thisNodeImages := map[string]struct{}{}
				for _, image := range images {
					for _, name := range image.Names {
						ref, _ := reference.ParseDockerRef(name)
						if ref != nil {
							name = ref.String()
						}
						thisNodeImages[name] = struct{}{}
					}
				}
				nodeImages[node.Name] = thisNodeImages
				return nil
			})
		}
	}

	if err := g.Wait(); err != nil {
		// best effort
		logger.Printf("Failed to run node images jobs: %s", err)
	}

	return nodeImages, nil
}

// NodesMissingImages returns the list of nodes missing any one of the images in the provided list
func NodesMissingImages(ctx context.Context, client kubernetes.Interface, logger *log.Logger, images []string, nodeImagesOpts NodeImagesJobOptions) ([]string, error) {
	refs := []reference.Reference{}
	for _, image := range images {
		ref, err := reference.ParseDockerRef(image)
		if err != nil {
			return nil, fmt.Errorf("failed to parse image %q: %w", image, err)
		}
		refs = append(refs, ref)
	}

	nodesImages, err := NodeImages(ctx, client, logger, nodeImagesOpts)
	if err != nil {
		return nil, fmt.Errorf("failed to find node images: %w", err)
	}

	missingNodes := map[string]struct{}{}
	for _, ref := range refs {
		for node, nodeImages := range nodesImages {
			_, foundImage := nodeImages[ref.String()]
			if !foundImage {
				missingNodes[node] = struct{}{}
			}
		}
	}

	missingNodesList := []string{}
	for missingNode := range missingNodes {
		missingNodesList = append(missingNodesList, missingNode)
	}

	return missingNodesList, nil
}

func runNodeImagesJob(ctx context.Context, client kubernetes.Interface, logger *log.Logger, node corev1.Node, opts NodeImagesJobOptions) ([]corev1.ContainerImage, error) {
	job := buildNodeImagesJob(ctx, opts.JobNamespace, opts.JobImage, node)
	timeout := opts.Timeout
	if timeout == 0 {
		timeout = DefaultNodeImagesJobTimeout
	}
	logs, _, err := k8sutil.RunJob(ctx, client, logger, job, timeout)
	if err != nil {
		return nil, err
	}
	containerLogs, ok := logs[job.Spec.Template.Spec.Containers[0].Name]
	if !ok {
		return nil, fmt.Errorf("failed to find container logs")
	}
	// NOTE: type k8s.io/cri-api/pkg/apis/runtime/v1.ListImagesResponse does not work here because
	// Images.Size_ is of type uint and not string
	criImages := struct {
		Images []struct {
			RepoDigests []string `json:"repoDigests"`
			RepoTags    []string `json:"repoTags"`
			Size        string   `json:"size"`
		} `json:"images"`
	}{}
	err = json.Unmarshal(containerLogs, &criImages)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal images: %w", err)
	}
	var images []corev1.ContainerImage
	for _, i := range criImages.Images {
		names := append([]string{}, i.RepoDigests...)
		names = append(names, i.RepoTags...)
		image := corev1.ContainerImage{
			Names: names,
		}
		size, _ := strconv.ParseInt(i.Size, 10, 64)
		image.SizeBytes = size
		images = append(images, image)
	}
	return images, nil
}

func buildNodeImagesJob(_ context.Context, jobNamespace string, jobImage string, node corev1.Node) *batchv1.Job {
	if jobNamespace == "" {
		jobNamespace = DefaultNodeImagesJobNamespace
	}
	if jobImage == "" {
		jobImage = DefaultNodeImagesJobImage
	}

	schedRules := &corev1.NodeSelector{
		NodeSelectorTerms: []corev1.NodeSelectorTerm{
			{
				MatchExpressions: []corev1.NodeSelectorRequirement{
					{
						Key:      "kubernetes.io/hostname",
						Operator: corev1.NodeSelectorOperator("In"),
						Values:   []string{node.Name},
					},
				},
			},
		},
	}

	typeSocket := corev1.HostPathSocket
	criSocket := getCRISocketFilePath(node)
	criSocketVolume := corev1.Volume{
		Name: "cri-socket",
		VolumeSource: corev1.VolumeSource{
			HostPath: &corev1.HostPathVolumeSource{
				Type: &typeSocket,
				Path: criSocket,
			},
		},
	}
	criSocketVolumeMount := corev1.VolumeMount{
		Name:      "cri-socket",
		MountPath: criSocket,
		ReadOnly:  true,
	}

	command := getNodeImagesCommand(criSocket)
	podSpec := corev1.PodSpec{
		RestartPolicy: corev1.RestartPolicyNever,
		Affinity: &corev1.Affinity{
			NodeAffinity: &corev1.NodeAffinity{
				RequiredDuringSchedulingIgnoredDuringExecution: schedRules,
			},
		},
		Volumes: []corev1.Volume{
			criSocketVolume,
		},
		Containers: []corev1.Container{
			{
				Name:    "node-images",
				Image:   jobImage,
				Command: []string{command[0]},
				Args:    command[1:],
				VolumeMounts: []corev1.VolumeMount{
					criSocketVolumeMount,
				},
			},
		},
	}

	tmp := uuid.New().String()[:5]
	jobName := fmt.Sprintf("node-images-%s-%s", node.Name, tmp)
	if len(jobName) > 63 {
		jobName = jobName[0:31] + jobName[len(jobName)-32:]
	}

	return &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      jobName,
			Namespace: jobNamespace,
			Labels: map[string]string{
				"app": "kurl-job-node-images",
			},
		},
		Spec: batchv1.JobSpec{
			BackoffLimit:          ptr.To(int32(1)),
			ActiveDeadlineSeconds: ptr.To(int64(120)),
			Template: corev1.PodTemplateSpec{
				Spec: podSpec,
			},
		},
	}
}

// NOTE: this only works for unix sockets
func getCRISocketFilePath(node corev1.Node) string {
	for key, value := range node.Annotations {
		if key == "kubeadm.alpha.kubernetes.io/cri-socket" {
			return strings.TrimPrefix(value, "unix://")
		}
	}

	if strings.Contains(node.Status.NodeInfo.ContainerRuntimeVersion, "containerd") {
		return "/run/containerd/containerd.sock"
	}
	return "/var/run/dockershim.sock"
}

// NOTE: this only works for unix sockets
func getNodeImagesCommand(criSocket string) []string {
	if !strings.HasPrefix(criSocket, "unix://") {
		criSocket = fmt.Sprintf("unix://%s", criSocket)
	}
	return []string{"crictl", fmt.Sprintf("--image-endpoint=%s", criSocket), "images", "-o=json"}
}
