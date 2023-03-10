package rook

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	cephv1 "github.com/rook/rook/pkg/client/clientset/versioned/typed/ceph.rook.io/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

var loopSleep = time.Second * 1

func HostpathToOsd(ctx context.Context, config *rest.Config) error {
	client := kubernetes.NewForConfigOrDie(config)
	cephClient := cephv1.NewForConfigOrDie(config)

	out("Adding blockdevice-based Rook OSDs and removing all Hostpath-based OSDs to allow upgrading Rook")
	// start rook-ceph-tools deployment if not present
	err := startToolbox(ctx, client)
	if err != nil {
		return fmt.Errorf("unable to start rook-ceph-tools before starting migration: %w", err)
	}

	// ensure rook is healthy before starting
	minuteContext, minuteCancel := context.WithTimeout(ctx, time.Minute)
	defer minuteCancel()
	err = WaitForRookHealth(minuteContext, client, nil)
	if err != nil {
		return fmt.Errorf("rook failed to become healthy within a minute, aborting migration: %w", err)
	}

	out("Rook is currently healthy, checking if a migration from directory-based storage is required")
	dirOSDs, blockOSDs, err := countRookOSDs(ctx, client)
	if err != nil {
		return fmt.Errorf("failed to determine how many OSDs needed migration: %w", err)
	}
	if dirOSDs == 0 {
		out("No directory OSDs exist, and so no migration is required.")
		return nil
	}
	out(fmt.Sprintf("%d directory OSDs exist, and %d nodes with block-based OSDs. Continuing with migration.", dirOSDs, blockOSDs))

	// change cephcluster to use OSDs not hostpath (if not already done)
	err = enableBlockDevices(ctx, client, cephClient)
	if err != nil {
		return fmt.Errorf("unable to enable ceph block devices: %w", err)
	}

	out("Waiting for required block device OSDs to be added to the cluster")
	// make sure there are at least min(num_nodes, 3) block device OSDs attached and available
	err = waitForBlockOSDs(ctx, client)
	if err != nil {
		return fmt.Errorf("failed to wait for block device OSDs to be added: %w", err)
	}

	out("Determining the list of hostpath OSDs to migrate")
	// determine the list of hostpath OSDs
	allOSDs, err := getRookOSDs(ctx, client)
	if err != nil {
		return fmt.Errorf("failed to get the current list of OSDs: %w", err)
	}
	hostPathOSDs := hostOSDs(allOSDs)

	osdListStrings := []string{}
	for _, osd := range hostPathOSDs {
		osdListStrings = append(osdListStrings, fmt.Sprintf("osd.%d", osd))
	}

	out(fmt.Sprintf("Removing hostpath OSDs %s from the cluster", strings.Join(osdListStrings, ", ")))
	for _, osdNum := range hostPathOSDs {
		err = safeRemoveOSD(ctx, client, osdNum)
		if err != nil {
			return fmt.Errorf("failed to safely remove OSD %d: %w", osdNum, err)
		}
	}

	out("Migration completed successfully!")

	return nil
}

// enableBlockDevices runs kubectl commands directly to edit the cephcluster object
// this is because later versions of the go library do not have the relevant fields
func enableBlockDevices(ctx context.Context, client kubernetes.Interface, cephClient *cephv1.CephV1Client) error {
	out("Disabling directory storage and enabling block OSDs")
	err := patchCephcluster(ctx, cephClient)
	if err != nil {
		return fmt.Errorf("failed to patch cephcluster to remove directory storage: %w", err)
	}

	blockDeviceOSDsExist, err := doBlockOSDsExist(ctx, client)
	if err != nil {
		return fmt.Errorf("failed to determine if block device OSDs existed: %w", err)
	}
	if !blockDeviceOSDsExist {
		out("Restarting the rook-ceph operator to ensure modified settings take effect immediately")
		err = restartOperator(ctx, client)
		if err != nil {
			return fmt.Errorf("failed to restart rook-ceph operator after patching ceph spec: %w", err)
		}
	}

	return nil
}

func patchCephcluster(ctx context.Context, cephClient *cephv1.CephV1Client) error {
	enableBlockUseAll := `
[
  {
    "op": "replace",
    "path": "/spec/storage/useAllDevices",
    "value": true
  }
]
`

	disableDirectories := `
[
  {
    "op": "remove",
    "path": "/spec/storage/directories"
  }
]
`
	_, err := cephClient.CephClusters("rook-ceph").Patch(ctx, "rook-ceph", types.JSONPatchType, []byte(enableBlockUseAll), metav1.PatchOptions{})
	if err != nil {
		return fmt.Errorf("unable to patch cephcluster: %w", err)
	}

	_, err = cephClient.CephClusters("rook-ceph").Patch(ctx, "rook-ceph", types.JSONPatchType, []byte(disableDirectories), metav1.PatchOptions{})
	if err != nil {
		out(fmt.Sprintf("Got error %q when disabling hostpath storage, but continuing anyways", err))
	}

	return nil
}

// checks if any block device OSDs exist - if they do, returns true
// intended to be used to determine if the 'enable block devices' patch needs to be run
func doBlockOSDsExist(ctx context.Context, client kubernetes.Interface) (bool, error) {
	_, blockOSDCount, err := countRookOSDs(ctx, client)
	if err != nil {
		return false, fmt.Errorf("failed to find block OSD count: %w", err)
	}

	return blockOSDCount > 0, nil
}

func restartOperator(ctx context.Context, client kubernetes.Interface) error {
	err := client.CoreV1().Pods("rook-ceph").DeleteCollection(ctx, metav1.DeleteOptions{}, metav1.ListOptions{LabelSelector: "app=rook-ceph-operator"})
	if err != nil {
		return fmt.Errorf("failed to delete rook-ceph-operator pods: %w", err)
	}

	return nil
}

func safeRemoveOSD(ctx context.Context, client kubernetes.Interface, osdNum int64) error {
	out(fmt.Sprintf("Reweighting osd.%d to 0", osdNum))
	// reweight hostpath OSDs to 0
	// ceph osd reweight osd.<num> 0
	_, _, err := runToolboxCommand(ctx, client, []string{"ceph", "osd", "reweight", fmt.Sprintf("osd.%d", osdNum), "0"})
	if err != nil {
		return fmt.Errorf("failed to run 'ceph osd reweight osd.%d 0': %w", osdNum, err)
	}

	out(fmt.Sprintf("Waiting for health to stabilize and data to migrate after reweighting osd.%d", osdNum))
	// wait for health
	err = waitForOkToRemoveOSD(ctx, client, osdNum)
	if err != nil {
		return fmt.Errorf("failed to wait for rook to become healthy after reweighting osd %d: %w", osdNum, err)
	}

	out(fmt.Sprintf("Scaling down osd.%d deployment at %s", osdNum, time.Now().Format(time.RFC3339)))
	// scale down hostpath OSDs (and wait for pod disappearance)
	_, err = client.AppsV1().Deployments("rook-ceph").Patch(ctx, fmt.Sprintf("rook-ceph-osd-%d", osdNum), types.JSONPatchType, []byte(`[{"op":"replace", "path":"/spec/replicas", "value":0}]`), metav1.PatchOptions{})
	if err != nil {
		return fmt.Errorf("failed to scale down rook-ceph-osd-%d deployment: %w", osdNum, err)
	}
	err = awaitDeploymentScale(ctx, client, "rook-ceph", fmt.Sprintf("rook-ceph-osd-%d", osdNum), 0)
	if err != nil {
		return fmt.Errorf("failed to wait for the rook-ceph-osd-%d deployment to scale down: %w", osdNum, err)
	}

	out(fmt.Sprintf("Waiting for osd to be down at %s", time.Now().Format(time.RFC3339)))
	err = waitForOSDDown(ctx, client)
	if err != nil {
		return fmt.Errorf("failed to wait for an OSD to be marked down after scale down: %w", err)
	}
	out(fmt.Sprintf("Removed osd was marked out by Rook at %s", time.Now().Format(time.RFC3339)))

	// ensure health is still green
	err = waitForOkToRemoveOSD(ctx, client, osdNum)
	if err != nil {
		return fmt.Errorf("failed to wait for rook to become healthy after scaling down osd %d: %w", osdNum, err)
	}

	out(fmt.Sprintf("Purging hostpath osd.%d as all data has been migrated to other devices", osdNum))
	// purge hostpath OSDs
	// osd purge <osdnum> --yes-i-really-mean-it
	_, _, err = runToolboxCommand(ctx, client, []string{"ceph", "osd", "purge", fmt.Sprintf("%d", osdNum), "--yes-i-really-mean-it"})
	if err != nil {
		return fmt.Errorf("failed to run 'ceph osd purge %d --yes-i-really-mean-it': %w", osdNum, err)
	}

	// delete the osd deployment so that it doesn't show up as a deployment running an old rook version during upgrades
	err = client.AppsV1().Deployments("rook-ceph").Delete(ctx, fmt.Sprintf("rook-ceph-osd-%d", osdNum), metav1.DeleteOptions{})
	if err != nil {
		return fmt.Errorf("failed to delete deployment for osd %d: %w", osdNum, err)
	}

	out(fmt.Sprintf("Successfully purged osd.%d", osdNum))
	return nil
}

func awaitDeploymentScale(ctx context.Context, client kubernetes.Interface, namespace, name string, desiredScale int32) error {
	out(fmt.Sprintf("Waiting for deployment %s in %s to reach scale of %d", name, namespace, desiredScale))
	errCount := 0
	for {
		dep, err := client.AppsV1().Deployments(namespace).Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			errCount++
			if errCount > 5 {
				return fmt.Errorf("failed to check deployment %s:%s status 5 times: %w", namespace, name, err)
			}
		} else {
			errCount = 0 // only fail for _consecutive_ errors

			if dep.Spec.Replicas != nil && *dep.Spec.Replicas != desiredScale {
				return fmt.Errorf("deployment %s:%s has scale %d, expected %d", namespace, name, dep.Spec.Replicas, desiredScale)
			}

			if dep.Status.Replicas == desiredScale && dep.Status.AvailableReplicas == desiredScale && dep.Status.ReadyReplicas == desiredScale && dep.Status.UpdatedReplicas == desiredScale {
				break
			}
		}

		select {
		case <-time.After(loopSleep):
			spinner()
		case <-ctx.Done():
			return fmt.Errorf("timed out waiting for deployment %s:%s to scale down - still has %d replicas", namespace, name, dep.Status.Replicas)
		}
	}
	return nil
}

// make sure there are at least min(num_nodes, 3) block device OSDs attached and available
// 1 node: 1 block device
// 3 nodes: 3 block devices
// 5 nodes: 3 block devices
func waitForBlockOSDs(ctx context.Context, client kubernetes.Interface) error {
	nodeCount, err := countNodes(ctx, client)
	if err != nil {
		return fmt.Errorf("unable to count nodes: %w", err)
	}

	desiredBlockCount := 3
	if nodeCount < 3 {
		desiredBlockCount = nodeCount
	}

	errCount := 0
	for {
		_, blockOSDCount, err := countRookOSDs(ctx, client)
		if err != nil {
			errCount++
			if errCount > 5 {
				return fmt.Errorf("failed to count rook OSDs 5 times: %w", err)
			}
		} else {
			errCount = 0 // only fail for _consecutive_ errors
			if blockOSDCount >= desiredBlockCount {
				break
			}
		}

		updatedLine(fmt.Sprintf("Waiting for block device OSDs to be added to the cluster on %d nodes, have %d", desiredBlockCount, blockOSDCount))
		select {
		case <-time.After(loopSleep):
		case <-ctx.Done():
			return fmt.Errorf("timed out waiting for sufficient block OSDs, have %d of %d", blockOSDCount, desiredBlockCount)
		}
	}
	return nil
}

type RookOSD struct {
	Num        int64
	Node       string
	IsHostpath bool
}

func getRookOSDs(ctx context.Context, client kubernetes.Interface) ([]RookOSD, error) {
	pods, err := client.CoreV1().Pods("rook-ceph").List(ctx, metav1.ListOptions{LabelSelector: "app=rook-ceph-osd"})
	if err != nil {
		return nil, fmt.Errorf("unable to get pods in rook-ceph: %w", err)
	}

	osds := []RookOSD{}
	for _, pod := range pods.Items {
		newOSD := RookOSD{
			Node: pod.Status.HostIP,
		}

		osdNum, err := strconv.ParseInt(pod.Labels["ceph-osd-id"], 10, 32)
		if err != nil {
			return nil, fmt.Errorf("Unable to parse OSD number of pod %q: %w", pod.Name, err)
		}
		newOSD.Num = osdNum

		for _, container := range pod.Spec.Containers {
			for _, mnt := range container.VolumeMounts {
				if mnt.MountPath == "/opt/replicated/rook" {
					newOSD.IsHostpath = true
				}
			}
		}

		osds = append(osds, newOSD)
	}

	return osds, nil
}

// returns the number of nodes with hostpath-based osds, the number of nodes with block device based osds, and an error.
func countRookOSDs(ctx context.Context, client kubernetes.Interface) (int, int, error) {
	osds, err := getRookOSDs(ctx, client)
	if err != nil {
		return -1, -1, fmt.Errorf("unable to get rook osds: %w", err)
	}

	blockOSDsHosts := map[string]struct{}{}
	hostpathOSDsHosts := map[string]struct{}{}
	for _, osd := range osds {
		if osd.IsHostpath {
			hostpathOSDsHosts[osd.Node] = struct{}{}
		} else {
			blockOSDsHosts[osd.Node] = struct{}{}
		}
	}

	return len(hostpathOSDsHosts), len(blockOSDsHosts), nil
}

func countNodes(ctx context.Context, client kubernetes.Interface) (int, error) {
	nodes, err := client.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return 0, fmt.Errorf("unable to list nodes: %w", err)
	}
	return len(nodes.Items), nil
}

// HasSufficientBlockOSDs returns true if there are enough block-device based OSDs attached to the cluster at present, false otherwise.
// 'enough' is min(nodecount, 3).
// this is the same requirement as in waitForBlockOSDs.
func HasSufficientBlockOSDs(ctx context.Context, client kubernetes.Interface) (bool, error) {
	nodeCount, err := countNodes(ctx, client)
	if err != nil {
		return false, fmt.Errorf("unable to count nodes: %w", err)
	}

	desiredBlockCount := 3
	if nodeCount < 3 {
		desiredBlockCount = nodeCount
	}

	_, blockOSDCount, err := countRookOSDs(ctx, client)
	if err != nil {
		return false, fmt.Errorf("unable to count OSDs: %w", err)
	}

	return blockOSDCount >= desiredBlockCount, nil
}

// returns the list of OSDs that are hostpath OSDs
func hostOSDs(osds []RookOSD) (hostOSDNums []int64) {
	for _, osd := range osds {
		if osd.IsHostpath {
			hostOSDNums = append(hostOSDNums, osd.Num)
		}
	}
	return
}
