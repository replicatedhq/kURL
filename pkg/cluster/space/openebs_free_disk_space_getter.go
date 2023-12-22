package clusterspace

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"log"
	"strconv"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/google/uuid"
	"github.com/replicatedhq/kurl/pkg/k8sutil"
	"gopkg.in/yaml.v2"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/utils/ptr"
)

type OpenEBSFreeDiskSpaceGetter struct {
	kcli            kubernetes.Interface
	deletePVTimeout time.Duration
	scname          string
	image           string
	log             *log.Logger
}

// OpenEBSVolume represents an OpenEBS volume in a node. Holds space related information and
// a flag indicating if the volume is part of the root (/) volume.
type OpenEBSVolume struct {
	Free       int64
	Used       int64
	RootVolume bool
}

// OpenEBSVolumes attempts to gather the free and used disk space for the openebs volume in
// all nodes in the cluster. this function creates a temporary pod in each of the nodes of
// the cluster, the pod runs a "df" command and we parse its output.
func (o *OpenEBSFreeDiskSpaceGetter) OpenEBSVolumes(ctx context.Context) (map[string]OpenEBSVolume, error) {
	nodes, err := o.kcli.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to list nodes: %w", err)
	}

	basePath, err := o.basePath(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to read openebs base path: %w", err)
	}

	var tmpPVCs []*corev1.PersistentVolumeClaim
	defer func() {
		o.log.Printf("Deleting temporary pvcs")
		if err := o.deleteTmpPVCs(tmpPVCs); err != nil {
			o.log.Printf("Failed to delete tmp claims: %s", err)
		}
	}()

	result := map[string]OpenEBSVolume{}
	for _, node := range nodes.Items {
		o.log.Printf("Analyzing free space on node %s", node.Name)
		if err := o.nodeIsSchedulable(node); err != nil {
			return nil, fmt.Errorf("failed to assess node %s: %w", node.Name, err)
		}

		pvc := o.buildTmpPVC(node.Name)
		if pvc, err = o.kcli.CoreV1().PersistentVolumeClaims("default").Create(
			ctx, pvc, metav1.CreateOptions{},
		); err != nil {
			return nil, fmt.Errorf("failed to create temporary pvc: %w", err)
		}
		tmpPVCs = append(tmpPVCs, pvc.DeepCopy())

		job := o.buildJob(ctx, node.Name, basePath, pvc.Name)
		out, status, err := k8sutil.RunJob(ctx, o.kcli, o.log, job, 5*time.Minute)
		if err != nil {
			o.logContainersState(out, status)
			return nil, fmt.Errorf(
				"failed to run job %s/%s on node %s: %w", job.Namespace, job.Name, node.Name, err,
			)
		}

		free, used, err := o.parseDFContainerOutput(out["df"])
		if err != nil {
			o.logContainersState(out, status)
			return nil, fmt.Errorf(
				"failed to parse node %s df output: %w", node.Name, err,
			)
		}

		volumes, err := o.parseFstabContainerOutput(out["fstab"])
		if err != nil {
			o.logContainersState(out, status)
			return nil, fmt.Errorf(
				"failed to parse node %s fstab output: %w", node.Name, err,
			)
		}

		rootVolume := true
		for _, mount := range volumes {
			if mount != "/" && strings.HasPrefix(basePath, mount) {
				rootVolume = false
				break
			}
		}

		result[node.Name] = OpenEBSVolume{
			Free:       free,
			Used:       used,
			RootVolume: rootVolume,
		}
	}
	return result, nil
}

// basePath inspects the destination storage class and checks what is the openebs base path
// configured for the storage.
func (o *OpenEBSFreeDiskSpaceGetter) basePath(ctx context.Context) (string, error) {
	sclass, err := o.kcli.StorageV1().StorageClasses().Get(ctx, o.scname, metav1.GetOptions{})
	if err != nil {
		return "", fmt.Errorf("failed to read destination storage class: %w", err)
	}

	cfg, ok := sclass.Annotations["cas.openebs.io/config"]
	if !ok {
		return "", fmt.Errorf("cas.openebs.io/config annotation not found in storage class")
	}

	var pairs = []struct {
		Name  string `yaml:"name"`
		Value string `yaml:"value"`
	}{}
	if err := yaml.Unmarshal([]byte(cfg), &pairs); err != nil {
		return "", fmt.Errorf("failed to parse openebs config annotation: %w", err)
	}

	for _, p := range pairs {
		if p.Name != "BasePath" {
			continue
		}

		if !strings.HasPrefix(p.Value, "/") {
			return "", fmt.Errorf("invalid opeenbs base path: %s", p.Value)
		}
		return p.Value, nil
	}
	return "", fmt.Errorf("openebs base path not defined in the storage class")
}

// nodeIsSchedulable verifies if the node has been flagged with some well known annotations.
// that could make the node not to be able to schedule our pod.
func (o *OpenEBSFreeDiskSpaceGetter) nodeIsSchedulable(node corev1.Node) error {
	annotations := map[string]string{
		"node.kubernetes.io/not-ready":                   "node is not ready",
		"node.kubernetes.io/unreachable":                 "node is unreachable",
		"node.kubernetes.io/unschedulable":               "node is unschedulable",
		"node.kubernetes.io/network-unavailable":         "node has no network",
		"node.kubernetes.io/out-of-service":              "node is out of service",
		"node.cloudprovider.kubernetes.io/uninitialized": "node not initialized",
		"node.cloudprovider.kubernetes.io/shutdown":      "node is shutting down",
	}
	for ant, msg := range annotations {
		if val, ok := node.Annotations[ant]; ok {
			return fmt.Errorf("annotation %s set with value %s: %s", ant, val, msg)
		}
	}
	return nil
}

// buildTmpPVC creates a temporary PVC requesting for 1Mi of space.
func (o *OpenEBSFreeDiskSpaceGetter) buildTmpPVC(node string) *corev1.PersistentVolumeClaim {
	tmp := uuid.New().String()[:5]
	pvcName := fmt.Sprintf("disk-free-%s-%s", node, tmp)
	if len(pvcName) > 63 {
		pvcName = pvcName[0:31] + pvcName[len(pvcName)-32:]
	}

	return &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      pvcName,
			Namespace: "default",
		},
		Spec: corev1.PersistentVolumeClaimSpec{
			StorageClassName: ptr.To(o.scname),
			AccessModes:      []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
			Resources: corev1.VolumeResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceStorage: resource.MustParse("1Mi"),
				},
			},
		},
	}
}

// buildJob returns a job scheduled to run in provided node. this job runs a pod with two
// containers, one to capture the disk size and the other to capture the content of the
// node fstab. timeout for the job is 2 minutes as in some cases we need to pull the image
// and then it takes longer to boostrap the job pod. this job also mounts the provided temp
// pvc, this is done to make sure that the openebs has created the base path inside the node
// (it only creates it when some kind of allocation already happened in the node).
func (o *OpenEBSFreeDiskSpaceGetter) buildJob(_ context.Context, node, basePath, tmpPVC string) *batchv1.Job {
	schedRules := &corev1.NodeSelector{
		NodeSelectorTerms: []corev1.NodeSelectorTerm{
			{
				MatchExpressions: []corev1.NodeSelectorRequirement{
					{
						Key:      "kubernetes.io/hostname",
						Operator: corev1.NodeSelectorOperator("In"),
						Values:   []string{node},
					},
				},
			},
		},
	}

	typeDir := corev1.HostPathDirectory
	typeFile := corev1.HostPathFile
	podSpec := corev1.PodSpec{
		RestartPolicy: corev1.RestartPolicyNever,
		Affinity: &corev1.Affinity{
			NodeAffinity: &corev1.NodeAffinity{
				RequiredDuringSchedulingIgnoredDuringExecution: schedRules,
			},
		},
		Volumes: []corev1.Volume{
			{
				Name: "openebs",
				VolumeSource: corev1.VolumeSource{
					HostPath: &corev1.HostPathVolumeSource{
						Type: &typeDir,
						Path: basePath,
					},
				},
			},
			{
				Name: "fstab",
				VolumeSource: corev1.VolumeSource{
					HostPath: &corev1.HostPathVolumeSource{
						Type: &typeFile,
						Path: "/etc/fstab",
					},
				},
			},
			{
				Name: "tmp",
				VolumeSource: corev1.VolumeSource{
					PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
						ClaimName: tmpPVC,
					},
				},
			},
		},
		Containers: []corev1.Container{
			{
				Name:    "df",
				Image:   o.image,
				Command: []string{"df"},
				Args:    []string{"-B1", "/data"},
				VolumeMounts: []corev1.VolumeMount{
					{
						MountPath: "/data",
						Name:      "openebs",
						ReadOnly:  true,
					},
					{
						MountPath: "/tmpmount",
						Name:      "tmp",
						ReadOnly:  true,
					},
				},
			},
			{
				Name:    "fstab",
				Image:   o.image,
				Command: []string{"cat"},
				Args:    []string{"/node/etc/fstab"},
				VolumeMounts: []corev1.VolumeMount{
					{
						MountPath: "/node/etc/fstab",
						Name:      "fstab",
						ReadOnly:  true,
					},
				},
			},
		},
	}

	tmp := uuid.New().String()[:5]
	jobName := fmt.Sprintf("disk-free-%s-%s", node, tmp)
	if len(jobName) > 63 {
		jobName = jobName[0:31] + jobName[len(jobName)-32:]
	}

	return &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      jobName,
			Namespace: "default",
			Labels: map[string]string{
				"app": "kurl-job-openebs-disk-free",
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

// deleteTmpPVCs deletes the provided pvcs from the default namespace and waits until all their
// backing pvs disappear as well (this is mandatory so we don't leave any orphan pv as this would
// make the pvmigrate to fail). this function has a timeout of 5 minutes, after that an error is
// returned.
func (o *OpenEBSFreeDiskSpaceGetter) deleteTmpPVCs(pvcs []*corev1.PersistentVolumeClaim) error {
	// Cleanup should use background context so as not to fail if context has already been canceled
	ctx := context.Background()

	pvs, err := o.kcli.CoreV1().PersistentVolumes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return fmt.Errorf("failed to list persistent volumes: %w", err)
	}

	pvsByPVCName := map[string]corev1.PersistentVolume{}
	for _, pv := range pvs.Items {
		if pv.Spec.ClaimRef == nil || pv.Spec.ClaimRef.Namespace != "default" {
			continue
		}
		pvsByPVCName[pv.Spec.ClaimRef.Name] = pv
	}

	var waitFor []string
	for _, pvc := range pvcs {
		propagation := metav1.DeletePropagationForeground
		delopts := metav1.DeleteOptions{PropagationPolicy: &propagation}
		if err := o.kcli.CoreV1().PersistentVolumeClaims("default").Delete(
			ctx, pvc.Name, delopts,
		); err != nil {
			if errors.IsNotFound(err) {
				continue
			}
			o.log.Printf("failed to delete temp pvc %s: %s", pvc.Name, err)
			continue
		}
		waitFor = append(waitFor, pvc.Name)
	}

	timeout := time.NewTicker(o.deletePVTimeout)
	interval := time.NewTicker(5 * time.Second)
	defer timeout.Stop()
	defer interval.Stop()
	for _, pvc := range waitFor {
		pv, ok := pvsByPVCName[pvc]
		if !ok {
			o.log.Printf("failed to find pv for temp pvc %s", pvc)
			continue
		}

		for {
			// break the loop as soon as we can't find the pv anymore.
			if _, err := o.kcli.CoreV1().PersistentVolumes().Get(
				ctx, pv.Name, metav1.GetOptions{},
			); err != nil && !errors.IsNotFound(err) {
				o.log.Printf("failed to get pv for temp pvc %s: %s", pvc, err)
			} else if err != nil && errors.IsNotFound(err) {
				break
			}

			select {
			case <-interval.C:
				continue
			case <-timeout.C:
				return fmt.Errorf("failed to delete pvs: timeout")
			}
		}
	}
	return nil
}

// logContainersState prints the provided pod logs and pod status conditions.
func (o *OpenEBSFreeDiskSpaceGetter) logContainersState(logs map[string][]byte, states map[string]corev1.ContainerState) {
	o.log.Println("")
	defer o.log.Println("")

	for container, clogs := range logs {
		o.log.Printf("%q container logs:", container)
		o.log.Print(string(clogs))
	}

	if len(states) == 0 {
		return
	}

	o.log.Printf("\nContainers state:")
	tw := tabwriter.NewWriter(o.log.Writer(), 2, 2, 1, ' ', 0)
	fmt.Fprintf(tw, "Container\tState\tReason\tMessage\n")
	for name, state := range states {
		switch {
		case state.Waiting != nil:
			fmt.Fprintf(tw, "%s\tWaiting\t%s\t%s\n", name, state.Waiting.Reason, state.Waiting.Message)
		case state.Running != nil:
			fmt.Fprintf(tw, "%s\tRunning\tTimeout\tContainer should have succeeded\n", name)
		case state.Terminated != nil:
			fmt.Fprintf(tw, "%s\tTerminated\t%s\t%s\n", name, state.Terminated.Reason, state.Terminated.Message)
		}
	}
	tw.Flush()
}

// parseDFContainerOutput parses the output (log) of the 'disk available' pod. the output of the
// container is expected to be the default df command output (with bytes as unit or measurement):
//
// Filesystem     1K-blocks     Used Available Use% Mounted on
// /dev/sda2       61608748 48707392   9739400  84% /data
//
// the openebs node volume is mounted under /data inside the pod. this function returns the
// amount of used and available space as bytes.
func (o *OpenEBSFreeDiskSpaceGetter) parseDFContainerOutput(output []byte) (int64, int64, error) {
	buf := bytes.NewBuffer(output)
	scanner := bufio.NewScanner(buf)
	for scanner.Scan() {
		words := strings.Fields(scanner.Text())
		if len(words) == 0 {
			continue
		}

		// lastpos is where the mount point lives.
		lastpos := len(words) - 1
		if words[lastpos] != "/data" || len(words) < 5 {
			continue
		}

		// pos is the position where the actual available space is.
		pos := len(words) - 3
		freeBytes, err := strconv.ParseInt(words[pos], 10, 64)
		if err != nil {
			return 0, 0, fmt.Errorf("failed to parse %q as available space: %w", words[pos], err)
		}

		// pos is now the position where the actual used space is.
		pos = len(words) - 4
		usedBytes, err := strconv.ParseInt(words[pos], 10, 64)
		if err != nil {
			return 0, 0, fmt.Errorf("failed to parse %q as used space: %w", words[pos], err)
		}

		return freeBytes, usedBytes, nil
	}

	if err := scanner.Err(); err != nil {
		return 0, 0, fmt.Errorf("failed to process container log: %w", err)
	}
	return 0, 0, fmt.Errorf("failed to locate free space info in pod log: %s", string(output))
}

// parseFstabContainerOutput parses the fstab container output and return all mount points.
func (o *OpenEBSFreeDiskSpaceGetter) parseFstabContainerOutput(output []byte) ([]string, error) {
	seen := map[string]bool{}
	mounts := []string{}
	buf := bytes.NewBuffer(output)
	scanner := bufio.NewScanner(buf)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "#") {
			continue
		}

		words := strings.Fields(line)
		if len(words) < 2 || !strings.HasPrefix(words[1], "/") {
			continue
		}

		if _, ok := seen[words[1]]; ok {
			continue
		}

		seen[words[1]] = true
		mounts = append(mounts, words[1])
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("failed to process container log: %w", err)
	}

	if len(mounts) == 0 {
		return nil, fmt.Errorf("failed to locate any mount point")
	}
	return mounts, nil
}

// NewOpenEBSFreeDiskSpaceGetter returns an object capable of retrieving the volumes assigned to OpenEBS
// in all cluster nodes. based on the volumes one can verify how much free space exists in the nodes.
func NewOpenEBSFreeDiskSpaceGetter(kcli kubernetes.Interface, log *log.Logger, image, scname string) (*OpenEBSFreeDiskSpaceGetter, error) {
	if image == "" {
		return nil, fmt.Errorf("empty image")
	}
	if scname == "" {
		return nil, fmt.Errorf("empty storage class")
	}
	if log == nil {
		return nil, fmt.Errorf("no logger provided")
	}

	return &OpenEBSFreeDiskSpaceGetter{
		deletePVTimeout: 5 * time.Minute,
		kcli:            kcli,
		log:             log,
		image:           image,
		scname:          scname,
	}, nil
}
