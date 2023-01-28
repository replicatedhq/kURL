package cli

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/replicatedhq/kurl/pkg/k8sutil"
	"github.com/spf13/cobra"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	storagev1 "k8s.io/api/storage/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/pointer"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/config"

	lhv1b1 "github.com/longhorn/longhorn-manager/k8s/pkg/apis/longhorn/v1beta1"
)

var (
	scaleDownReplicasWaitTime = 2 * time.Minute
)

const (
	volumeReplicasAnnotation     = "kurl.sh/volume-replica-count"
	pvmigrateScaleDownAnnotation = "kurl.sh/pvcmigrate-scale"
	longhornNamespace            = "longhorn-system"
	overProvisioningSetting      = "storage-over-provisioning-percentage"
)

func NewLonghornCmd(cli CLI) *cobra.Command {
	return &cobra.Command{
		Use:   "longhorn",
		Short: "Perform operations on a longhorn installation within a kURL cluster",
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
	}
}

func NewLonghornRollbackMigrationReplicas(_ CLI) *cobra.Command {
	return &cobra.Command{
		Use:          "rollback-migration-replicas",
		Short:        "Rollback Longhorn volume replicas to their original value.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			log.Print("Rolling back Longhorn volume replicas to their original value.")
			cli, err := client.New(config.GetConfigOrDie(), client.Options{})
			if err != nil {
				return fmt.Errorf("error creating client: %s", err)
			}
			lhv1b1.AddToScheme(cli.Scheme())

			var l1b1Volumes lhv1b1.VolumeList
			if err := cli.List(cmd.Context(), &l1b1Volumes, client.InNamespace(longhornNamespace)); err != nil {
				return fmt.Errorf("error listing longhorn volumes: %w", err)
			}

			for _, volume := range l1b1Volumes.Items {
				if _, ok := volume.Annotations[volumeReplicasAnnotation]; !ok {
					log.Printf("Volume %s has not been scaled down, skipping.", volume.Name)
					continue
				}

				replicas, err := strconv.Atoi(volume.Annotations[volumeReplicasAnnotation])
				if err != nil {
					return fmt.Errorf("error parsing replica count for volume %s: %w", volume.Name, err)
				}

				log.Printf("Rolling back volume %s to %d replicas.", volume.Name, replicas)
				delete(volume.Annotations, volumeReplicasAnnotation)
				volume.Spec.NumberOfReplicas = replicas
				if err := cli.Update(cmd.Context(), &volume); err != nil {
					return fmt.Errorf("error rolling back volume %s replicas: %w", volume.Name, err)
				}
			}
			log.Printf("Longhorn volumes have been rolled back to their original replica count.")
			return nil
		},
	}
}

func NewLonghornPrepareForMigration(_ CLI) *cobra.Command {
	return &cobra.Command{
		Use:          "prepare-for-migration",
		Short:        "Prepares Longhorn for migration to a different storage provisioner.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			log.Print("Preparing Longhorn deployment for migration.")
			cli, err := client.New(config.GetConfigOrDie(), client.Options{})
			if err != nil {
				return fmt.Errorf("error creating client: %s", err)
			}
			lhv1b1.AddToScheme(cli.Scheme())

			var scaledDown bool
			var nodes corev1.NodeList
			if err := cli.List(cmd.Context(), &nodes); err != nil {
				return fmt.Errorf("error listing kubernetes nodes: %s", err)
			} else if len(nodes.Items) == 1 {
				log.Print("Only one node found, scaling down the number of volume replicas to 1.")
				if scaledDown, err = scaleDownReplicas(cmd.Context(), cli); err != nil {
					return fmt.Errorf("error scaling down longhorn replicas: %s", err)
				}
			}

			unhealthy, err := unhealthyVolumes(cmd.Context(), cli)
			if err != nil {
				return fmt.Errorf("error assessing unhealthy volumes: %s", err)
			}

			if len(unhealthy) > 0 {
				log.Printf("The following Longhorn volumes are unhealthy:")
				for _, vol := range unhealthy {
					log.Printf(" - %s/%s", longhornNamespace, vol)
				}
				return fmt.Errorf("error preparing longhorn for migration: unhealthy volumes")
			}

			unhealthy, err = unhealthyNodes(cmd.Context(), cli)
			if err != nil {
				return fmt.Errorf("error assessing unhealthy Longhorn nodes: %s", err)
			}

			if len(unhealthy) > 0 {
				log.Printf("The following Longhorn nodes are unhealthy:")
				for _, node := range unhealthy {
					log.Printf(" - %s", node)
				}
				return fmt.Errorf("error preparing longhorn for migration: unhealthy nodes")
			}

			if scaledDown {
				log.Printf("Storage volumes have been scaled down to 1 replica for the migration.")
				log.Printf("If necessary, you can scale them back up to the original value with:")
				log.Printf("")
				log.Printf("$ kurl longhorn rollback-migration-replicas")
				log.Printf("")
			}
			log.Print("All Longhorn volumes and nodes are healthy, ready for migration.")

			if err := scaleDownPodsUsingLonghorn(cmd.Context(), cli); err != nil {
				return fmt.Errorf("error scaling down pods using longhorn volumes: %s", err)
			}
			return nil
		},
	}
}

// scaleDownPodsUsingLonghorn scales down all pods using Longhorn volumes.
func scaleDownPodsUsingLonghorn(ctx context.Context, cli client.Client) error {
	log.Printf("Scaling down pods using Longhorn volumes.")
	objects, err := getObjectsUsingLonghorn(ctx, cli)
	if err != nil {
		return fmt.Errorf("error getting objects using longhorn: %w", err)
	}
	for _, obj := range objects {
		switch obj := obj.(type) {
		case *appsv1.Deployment:
			if err := scaleDownDeployment(ctx, cli, obj); err != nil {
				return fmt.Errorf("error scaling down deployment %s: %w", obj.Name, err)
			}
		case *appsv1.StatefulSet:
			if err := scaleDownStatefulSet(ctx, cli, obj); err != nil {
				return fmt.Errorf("error scaling down statefulset %s: %w", obj.Name, err)
			}
		default:
			gvk := obj.GetObjectKind().GroupVersionKind()
			return fmt.Errorf("pods controlled by a %s are not supported", gvk.Kind)
		}
	}
	return nil
}

// scaleDownDeployment scales down a deployment to 0 replicas.
func scaleDownDeployment(ctx context.Context, cli client.Client, dep *appsv1.Deployment) error {
	log.Printf("Scaling down deployment %s/%s", dep.Namespace, dep.Name)
	replicas := int32(1)
	if dep.Spec.Replicas != nil {
		replicas = *dep.Spec.Replicas
	}
	if dep.Annotations == nil {
		dep.Annotations = map[string]string{}
	}
	if _, ok := dep.Annotations[pvmigrateScaleDownAnnotation]; !ok {
		dep.Annotations[pvmigrateScaleDownAnnotation] = fmt.Sprintf("%d", replicas)
	}
	dep.Spec.Replicas = pointer.Int32(0)
	log.Printf("scaling down deployment %s/%s", dep.Namespace, dep.Name)
	if err := cli.Update(ctx, dep); err != nil {
		return fmt.Errorf("error scaling down deployment %s/%s: %w", dep.Namespace, dep.Name, err)
	}
	return nil
}

// scaleDownStatefulSet scales down a statefulset to 0 replicas.
func scaleDownStatefulSet(ctx context.Context, cli client.Client, sset *appsv1.StatefulSet) error {
	log.Printf("Scaling down statefulset %s/%s", sset.Namespace, sset.Name)
	replicas := int32(1)
	if sset.Spec.Replicas != nil {
		replicas = *sset.Spec.Replicas
	}
	if sset.Annotations == nil {
		sset.Annotations = map[string]string{}
	}
	if _, ok := sset.Annotations[pvmigrateScaleDownAnnotation]; !ok {
		sset.Annotations[pvmigrateScaleDownAnnotation] = fmt.Sprintf("%d", replicas)
	}
	sset.Spec.Replicas = pointer.Int32(0)
	log.Printf("scaling down statefulset %s/%s", sset.Namespace, sset.Name)
	if err := cli.Update(ctx, sset); err != nil {
		return fmt.Errorf("failed to scale statefulset %s/%s: %w", sset.Namespace, sset.Name, err)
	}
	return nil
}

// getObjectsUsingLonghorn returns all objects that use Longhorn volumes. Only deployments, statefulsets,
// and replicasets are supported (as those are the only types supported by pvmigrate).
func getObjectsUsingLonghorn(ctx context.Context, cli client.Client) ([]client.Object, error) {
	pods, err := getPodsUsingLonghorn(ctx, cli)
	if err != nil {
		return nil, fmt.Errorf("error getting pods using longhorn: %w", err)
	}
	seen := map[string]bool{}
	var objects []client.Object
	for _, pod := range pods {
		if len(pod.OwnerReferences) == 0 {
			return nil, fmt.Errorf(
				"pod %s in %s did not have any owners!\nPlease delete it before retrying",
				pod.Name, pod.Namespace,
			)
		}
		for _, owner := range pod.OwnerReferences {
			objIndex := fmt.Sprintf("%s/%s/%s", owner.Kind, pod.Namespace, owner.Name)
			if _, ok := seen[objIndex]; ok {
				continue
			}
			seen[objIndex] = true
			obj, err := getOwnerObject(ctx, cli, pod.Namespace, owner)
			if err != nil {
				return nil, fmt.Errorf("error getting owner object for pod %s/%s: %w", pod.Namespace, pod.Name, err)
			}
			objects = append(objects, obj)
		}
	}
	return objects, nil
}

// getOwnerObject returns the object referred by the provided owner reference. Only deployments, statefulsets,
// and replicasets are supported (as those are the only types supported by pvmigrate).
func getOwnerObject(ctx context.Context, cli client.Client, namespace string, owner metav1.OwnerReference) (client.Object, error) {
	switch owner.Kind {
	case "StatefulSet":
		nsn := types.NamespacedName{Namespace: namespace, Name: owner.Name}
		var sset appsv1.StatefulSet
		if err := cli.Get(ctx, nsn, &sset); err != nil {
			return nil, fmt.Errorf("error getting statefulset %s: %w", nsn, err)
		}
		return &sset, nil
	case "ReplicaSet":
		nsn := types.NamespacedName{Namespace: namespace, Name: owner.Name}
		var rset appsv1.ReplicaSet
		if err := cli.Get(ctx, nsn, &rset); err != nil {
			return nil, fmt.Errorf("error getting replicaset %s: %w", nsn, err)
		}
		if len(rset.OwnerReferences) != 1 {
			return nil, fmt.Errorf(
				"expected 1 owner for replicaset %s in %s, found %d instead",
				owner.Name, namespace, len(rset.OwnerReferences),
			)
		}
		if rset.OwnerReferences[0].Kind != "Deployment" {
			return nil, fmt.Errorf(
				"expected replicaset %s in %s to have a deployment as owner, found %s instead",
				owner.Name, namespace, rset.OwnerReferences[0].Kind,
			)
		}
		nsn = types.NamespacedName{Namespace: namespace, Name: rset.OwnerReferences[0].Name}
		var deployment appsv1.Deployment
		if err := cli.Get(ctx, nsn, &deployment); err != nil {
			return nil, fmt.Errorf("error getting deployment %s: %w", nsn, err)
		}
		return &deployment, nil
	default:
		return nil, fmt.Errorf(
			"scaling pods controlled by a %s is not supported, please delete the pods controlled by "+
				"%s in %s before retrying", owner.Kind, owner.Kind, namespace,
		)
	}
}

// getPodsUsingLonghorn returns all pods that mount Longhorn volumes.
func getPodsUsingLonghorn(ctx context.Context, cli client.Client) ([]corev1.Pod, error) {
	pvcs, err := getLonghornPersistenVolumeClaims(ctx, cli)
	if err != nil {
		return nil, fmt.Errorf("error getting longhorn persistent volume claims: %w", err)
	}
	var pods corev1.PodList
	if err := cli.List(ctx, &pods); err != nil {
		return nil, fmt.Errorf("error listing pods: %w", err)
	}
	var podsUsingLonghorn []corev1.Pod
	for _, pvc := range pvcs {
		for _, pod := range pods.Items {
			if k8sutil.PodHasPVC(pod, pvc.Namespace, pvc.Name) {
				podsUsingLonghorn = append(podsUsingLonghorn, pod)
			}
		}
	}
	return podsUsingLonghorn, nil
}

// getLonghornPersistenVolumeClaims returns all persistent volume claims that are claiming Longhorn volumes.
func getLonghornPersistenVolumeClaims(ctx context.Context, cli client.Client) ([]corev1.PersistentVolumeClaim, error) {
	pvs, err := getLonghornPersistenVolumes(ctx, cli)
	if err != nil {
		return nil, fmt.Errorf("error getting longhorn persistent volumes: %w", err)
	}
	var pvcs []corev1.PersistentVolumeClaim
	for _, pv := range pvs {
		if pv.Spec.ClaimRef == nil {
			return nil, fmt.Errorf("pv %s does not have an associated pvc, resolve this before rerunning", pv.Name)
		}
		nsn := types.NamespacedName{Namespace: pv.Spec.ClaimRef.Namespace, Name: pv.Spec.ClaimRef.Name}
		var pvc corev1.PersistentVolumeClaim
		if err := cli.Get(ctx, nsn, &pvc); err != nil {
			return nil, fmt.Errorf("error getting persistent volume claim %s: %w", nsn, err)
		}
		pvcs = append(pvcs, pvc)
	}
	return pvcs, nil
}

// getLonghornPersistenVolumes returns all persistent volumes that are backed by Longhorn.
func getLonghornPersistenVolumes(ctx context.Context, cli client.Client) ([]corev1.PersistentVolume, error) {
	storageClasses, err := getLonghornStorageClasses(ctx, cli)
	if err != nil {
		return nil, fmt.Errorf("error getting longhorn storage classes: %w", err)
	}
	var allPVs corev1.PersistentVolumeList
	if err := cli.List(ctx, &allPVs); err != nil {
		return nil, fmt.Errorf("error listing persistent volumes: %w", err)
	}
	var longhornPVs []corev1.PersistentVolume
	for _, pv := range allPVs.Items {
		for _, storageClass := range storageClasses {
			if pv.Spec.StorageClassName == storageClass.Name {
				longhornPVs = append(longhornPVs, pv)
			}
		}
	}
	return longhornPVs, nil
}

// getLonghornStorageClasses returns all storage classes that use the Longhorn provisioner.
func getLonghornStorageClasses(ctx context.Context, cli client.Client) ([]storagev1.StorageClass, error) {
	var storageClasses storagev1.StorageClassList
	if err := cli.List(ctx, &storageClasses); err != nil {
		return nil, fmt.Errorf("error listing storage classes: %w", err)
	}
	var longhornStorageClasses []storagev1.StorageClass
	for _, storageClass := range storageClasses.Items {
		if strings.Contains(storageClass.Provisioner, "longhorn") {
			longhornStorageClasses = append(longhornStorageClasses, storageClass)
		}
	}
	return longhornStorageClasses, nil
}

// scaleDownReplicas scales down the number of replicas for all volumes to 1. Returns a bool indicating if any
// of the volumes were scaled down.
func scaleDownReplicas(ctx context.Context, cli client.Client) (bool, error) {
	var l1b1Volumes lhv1b1.VolumeList
	if err := cli.List(ctx, &l1b1Volumes, client.InNamespace(longhornNamespace)); err != nil {
		return false, fmt.Errorf("error listing longhorn volumes: %w", err)
	}

	var volumesToScale []lhv1b1.Volume
	for _, volume := range l1b1Volumes.Items {
		if volume.Spec.NumberOfReplicas == 1 {
			log.Printf("Volume %s already has 1 replica, skipping.", volume.Name)
			continue
		}
		volumesToScale = append(volumesToScale, volume)
	}

	if len(volumesToScale) == 0 {
		return false, nil
	}

	for _, volume := range volumesToScale {
		log.Printf("Scaling down replicas for volume %s.", volume.Name)
		for {
			nsn := types.NamespacedName{Namespace: longhornNamespace, Name: volume.Name}
			var updatedVolume lhv1b1.Volume
			if err := cli.Get(ctx, nsn, &updatedVolume); err != nil {
				return false, fmt.Errorf("error getting volume %s: %w", volume.Name, err)
			}

			if updatedVolume.Annotations == nil {
				updatedVolume.Annotations = map[string]string{}
			}
			if _, ok := updatedVolume.Annotations[volumeReplicasAnnotation]; !ok {
				updatedVolume.Annotations[volumeReplicasAnnotation] = strconv.Itoa(updatedVolume.Spec.NumberOfReplicas)
			}
			updatedVolume.Spec.NumberOfReplicas = 1
			if err := cli.Update(ctx, &updatedVolume); err != nil {
				if errors.IsConflict(err) {
					time.Sleep(time.Second)
					continue
				}
				return false, fmt.Errorf("error updating replicas for volume %s: %w", volume.Name, err)
			}
			break
		}
	}

	log.Printf("Awaiting %v for replicas to scale down.", scaleDownReplicasWaitTime)
	time.Sleep(scaleDownReplicasWaitTime)
	return true, nil
}

// unhealthyVolumes returns a list of attached volumes that are not in a healthy state.
func unhealthyVolumes(ctx context.Context, cli client.Client) ([]string, error) {
	var volumes lhv1b1.VolumeList
	if err := cli.List(ctx, &volumes, client.InNamespace(longhornNamespace)); err != nil {
		return nil, fmt.Errorf("error listing volumes: %w", err)
	}
	var result []string
	for _, volume := range volumes.Items {
		log.Printf("Checking health of volume %s.", volume.Name)
		if volume.Status.State != lhv1b1.VolumeStateAttached || isVolumeHealthy(volume) {
			continue
		}
		result = append(result, volume.Name)
	}
	return result, nil
}

// isVolumeHealthy returns true if the volume is in a healthy state.
func isVolumeHealthy(vol lhv1b1.Volume) bool {
	for _, cond := range vol.Status.Conditions {
		if cond.Type != lhv1b1.VolumeConditionTypeScheduled {
			continue
		}
		if cond.Status == lhv1b1.ConditionStatusTrue {
			break
		}
		return false
	}
	return vol.Status.Robustness == lhv1b1.VolumeRobustnessHealthy
}

// unhealthyNodes returns a list of nodes that are not in a healthy state.
func unhealthyNodes(ctx context.Context, cli client.Client) ([]string, error) {
	var longhornNodes lhv1b1.NodeList
	if err := cli.List(ctx, &longhornNodes); err != nil {
		return nil, fmt.Errorf("error listing longhorn nodes: %w", err)
	}
	var result []string
	for _, node := range longhornNodes.Items {
		log.Printf("Checking health of node %s.", node.Name)
		if healthy, err := isNodeHealthy(ctx, cli, node); err != nil {
			return nil, fmt.Errorf("error checking node health: %w", err)
		} else if !healthy {
			result = append(result, node.Name)
		}
	}
	return result, nil
}

// isNodeHealthy returns true if the node is in a healthy state.
func isNodeHealthy(ctx context.Context, cli client.Client, node lhv1b1.Node) (bool, error) {
	if !nodeIs(lhv1b1.NodeConditionTypeReady, node) {
		return false, nil
	}
	if !nodeIs(lhv1b1.NodeConditionTypeSchedulable, node) {
		return false, nil
	}
	if !disksAre(lhv1b1.DiskConditionTypeReady, node.Status.DiskStatus) {
		return false, nil
	}
	if !disksAre(lhv1b1.DiskConditionTypeSchedulable, node.Status.DiskStatus) {
		return false, nil
	}
	if over, err := disksAreOvercommited(ctx, cli, node.Status.DiskStatus); err != nil {
		return false, fmt.Errorf("error checking disk overcommit: %w", err)
	} else if over {
		return false, nil
	}
	return true, nil
}

// disksAreOvercommited returns true if any disk in the node is overcommited.
func disksAreOvercommited(ctx context.Context, cli client.Client, disks map[string]*lhv1b1.DiskStatus) (bool, error) {
	var config lhv1b1.Setting
	nsn := client.ObjectKey{Name: overProvisioningSetting, Namespace: longhornNamespace}
	if err := cli.Get(ctx, nsn, &config); err != nil {
		return false, fmt.Errorf("error getting over provisioning setting: %w", err)
	}

	value, err := strconv.Atoi(config.Value)
	if err != nil {
		return false, fmt.Errorf("error parsing overcommit setting: %w", err)
	}
	pct := float64(value) / 100
	for _, disk := range disks {
		max := float64(disk.StorageAvailable) * pct
		if disk.StorageScheduled >= int64(max) {
			return true, nil
		}
	}
	return false, nil
}

// disksAre returns true if all disks are in the given condition.
func disksAre(condition string, disks map[string]*lhv1b1.DiskStatus) bool {
	for _, disk := range disks {
		for _, cond := range disk.Conditions {
			if cond.Type != condition {
				continue
			}
			return cond.Status == lhv1b1.ConditionStatusTrue
		}
	}
	return false
}

// nodeIs returns true if the node is in the given condition.
func nodeIs(condition string, node lhv1b1.Node) bool {
	for _, cond := range node.Status.Conditions {
		if cond.Type != condition {
			continue
		}
		return cond.Status == lhv1b1.ConditionStatusTrue
	}
	return false
}
