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

	"code.cloudfoundry.org/bytefmt"
	"gopkg.in/yaml.v2"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"

	"github.com/replicatedhq/kurl/pkg/k8sutil"
)

// OpenEBSChecker checks if we have enough disk space on the cluster to migrate volumes to openebs.
type OpenEBSChecker struct {
	cli    kubernetes.Interface
	log    *log.Logger
	image  string
	srcSC  string
	dstSC  string
	kutils *K8SUtils
}

// parseDFContainerOutput parses the output (log) of the 'disk available' pod. the output of the
// container is expected to be the default df command output (with bytes as unit or measurement):
//
// Filesystem     1K-blocks     Used Available Use% Mounted on
// /dev/sda2       61608748 48707392   9739400  84% /data
//
// the openebs node volume is mounted under /data inside the pod. this function returns the
// amount of used and available space as bytes.
func (o *OpenEBSChecker) parseDFContainerOutput(output []byte) (int64, int64, error) {
	buf := bytes.NewBuffer(output)
	scanner := bufio.NewScanner(buf)
	for scanner.Scan() {
		words := strings.Fields(scanner.Text())
		if len(words) == 0 {
			continue
		}

		// lastpos is where the mount point lives.
		lastpos := len(words) - 1
		if words[lastpos] != "/data" {
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
			return 0, 0, fmt.Errorf("failed to parse %q as available space: %w", words[pos], err)
		}

		return freeBytes, usedBytes, nil
	}
	return 0, 0, fmt.Errorf("failed to locate free space info in pod log: %s", string(output))
}

// parseFstabContainerOutput parses the fstab container output and return all mount points.
func (o *OpenEBSChecker) parseFstabContainerOutput(output []byte) ([]string, error) {
	mounts := []string{}
	buf := bytes.NewBuffer(output)
	scanner := bufio.NewScanner(buf)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "/") {
			continue
		}

		words := strings.Fields(line)
		if len(words) < 2 {
			return nil, fmt.Errorf("failed to parse fstab line: %s", line)
		}
		mounts = append(mounts, words[1])
	}
	if len(mounts) == 0 {
		return nil, fmt.Errorf("failed to locate any mount point")
	}
	return mounts, nil
}

// OpenEBSVolume represents an OpenEBS volume in a node. Holds space related information and
// a flag indicating if the volume is part of the root (/) volume.
type OpenEBSVolume struct {
	Free       int64
	Used       int64
	RootVolume bool
}

// openEBSVolumes attempts to gather the free and used disk space for the openebs volume in
// all nodes in the cluster. this function creates a temporary pod in each of the nodes of
// the cluster, the pod runs a "df" command and we parse its output.
func (o *OpenEBSChecker) openEBSVolumes(ctx context.Context) (map[string]OpenEBSVolume, error) {
	nodes, err := o.cli.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to list nodes: %w", err)
	}

	basePath, err := o.basePath(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to read openebs base path: %w", err)
	}

	result := map[string]OpenEBSVolume{}
	for _, node := range nodes.Items {
		pod := o.buildPod(ctx, node.Name, basePath)
		out, status, err := k8sutil.RunEphemeralPod(ctx, o.cli, o.log, 30*time.Second, pod)
		if err != nil {
			o.logPodInfo(out, status)
			return nil, fmt.Errorf("failed to run pod on node %s: %w", node.Name, err)
		}

		free, used, err := o.parseDFContainerOutput(out["df"])
		if err != nil {
			o.logPodInfo(out, status)
			return nil, fmt.Errorf("failed to parse node %s df output: %w", node.Name, err)
		}

		volumes, err := o.parseFstabContainerOutput(out["fstab"])
		if err != nil {
			o.logPodInfo(out, status)
			return nil, fmt.Errorf("failed to parse node %s fstab output: %w", node.Name, err)
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

// logPodInfo prints the provided pod logs and pod status conditions.
func (o *OpenEBSChecker) logPodInfo(logs map[string][]byte, status *corev1.PodStatus) {
	for container, clogs := range logs {
		o.log.Printf("%q container logs:", container)
		o.log.Print(string(clogs))
	}

	if status == nil {
		return
	}

	o.log.Printf("Pod conditions:")
	tw := tabwriter.NewWriter(o.log.Writer(), 2, 2, 1, ' ', 0)
	fmt.Fprintf(tw, "TYPE\tSTATUS\tREASON\tMESSAGE\n")
	for _, cond := range status.Conditions {
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\n", cond.Type, cond.Status, cond.Reason, cond.Message)
	}
	tw.Flush()
}

// basePath inspects the destination storage class and checks what is the openebs base path
// configured for the storage.
func (o *OpenEBSChecker) basePath(ctx context.Context) (string, error) {
	sclass, err := o.cli.StorageV1().StorageClasses().Get(ctx, o.dstSC, metav1.GetOptions{})
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
		return p.Value, nil
	}
	return "", fmt.Errorf("openebs base path not defined in the storage class")
}

// buildPod returns a pod that runs a "df" in the openebs hostpath mounted volume and a
// "cat" on host's /etc/fstab file.
func (o *OpenEBSChecker) buildPod(ctx context.Context, node, basePath string) *corev1.Pod {
	podName := fmt.Sprintf("disk-free-%s", node)
	if len(podName) > 63 {
		podName = podName[0:31] + podName[len(podName)-32:]
	}

	typedir := corev1.HostPathDirectory
	typefile := corev1.HostPathFile
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      podName,
			Namespace: "default",
			Labels: map[string]string{
				"pvmigrate": "volume-bind",
			},
		},
		Spec: corev1.PodSpec{
			RestartPolicy: corev1.RestartPolicyNever,
			Affinity: &corev1.Affinity{
				NodeAffinity: &corev1.NodeAffinity{
					RequiredDuringSchedulingIgnoredDuringExecution: &corev1.NodeSelector{
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
					},
				},
			},
			Volumes: []corev1.Volume{
				{
					Name: "openebs",
					VolumeSource: corev1.VolumeSource{
						HostPath: &corev1.HostPathVolumeSource{
							Type: &typedir,
							Path: basePath,
						},
					},
				},
				{
					Name: "fstab",
					VolumeSource: corev1.VolumeSource{
						HostPath: &corev1.HostPathVolumeSource{
							Type: &typefile,
							Path: "/etc/fstab",
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
		},
	}
}

// hasEnoughSpace calculates if the openebs volume is capable of holding the provided reserved
// amount of bytes. if the openebs volume is part of the root filesystem then we decrease 15%
// of its space. returns the effective free space as well.
func (o *OpenEBSChecker) hasEnoughSpace(vol OpenEBSVolume, reserved int64) (int64, bool) {
	total := float64(vol.Free + vol.Used)
	if vol.RootVolume {
		total *= 0.85
	}
	free := int64(total) - vol.Used
	return free, free > reserved
}

// Check verifies if we have enough disk space to execute the migration. returns a list of nodes
// where the migration can't execute due to a possible lack of disk space.
func (o *OpenEBSChecker) Check(ctx context.Context) ([]string, error) {
	o.log.Printf("Analyzing reserved and free disk space per node...")
	volumes, err := o.openEBSVolumes(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate available disk space per node: %w", err)
	}

	reservedPerNode, reservedDetached, err := o.kutils.PVSReservationPerNode(ctx, o.srcSC)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate reserved disk space per node: %w", err)
	}

	faultyNodes := map[string]bool{}
	for node, vol := range volumes {
		var ok bool
		var free int64
		if free, ok = o.hasEnoughSpace(vol, reservedPerNode[node]); ok {
			continue
		}

		faultyNodes[node] = true
		o.log.Printf(
			"Node %q has %s available, failed to migrate %s (%q storage class)",
			node,
			bytefmt.ByteSize(uint64(free)),
			bytefmt.ByteSize(uint64(reservedPerNode[node])),
			o.srcSC,
		)
	}

	if reservedDetached != 0 {
		// XXX we make sure that the detached reserved space can be migrated to
		// *any* of the nodes as we don't know where the migration pod will be
		// scheduled.
		o.log.Printf(
			"Amount of detached PVs reservations (%q storage class): %s",
			o.srcSC,
			bytefmt.ByteSize(uint64(reservedDetached)),
		)

		for node, vol := range volumes {
			vol.Used += reservedPerNode[node]
			vol.Free -= reservedPerNode[node]
			if free, hasSpace := o.hasEnoughSpace(vol, reservedDetached); !hasSpace {
				if free < 0 {
					free = 0
				}
				o.log.Printf(
					"Node %q has %s left (after migrating reserved storage), "+
						"failed to host extra %s of detached PVs",
					node,
					bytefmt.ByteSize(uint64(free)),
					bytefmt.ByteSize(uint64(reservedDetached)),
				)
				faultyNodes[node] = true
			}
		}
	}

	if len(faultyNodes) == 0 {
		o.log.Printf("Enough disk space found, moving on")
		return nil, nil
	}

	var nodeNames []string
	for name := range faultyNodes {
		nodeNames = append(nodeNames, name)
	}
	return nodeNames, nil
}

// NewOpenEBSChecker returns a disk free analyser for openebs storage local volume provisioner.
func NewOpenEBSChecker(cli kubernetes.Interface, log *log.Logger, cfg *rest.Config, image, srcSC, dstSC string) *OpenEBSChecker {
	return &OpenEBSChecker{
		cli:    cli,
		log:    log,
		image:  image,
		srcSC:  srcSC,
		dstSC:  dstSC,
		kutils: NewK8sUtils(log, cli, cfg),
	}
}
