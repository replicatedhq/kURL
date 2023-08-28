package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	storagev1 "k8s.io/api/storage/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/util/retry"
	"k8s.io/utils/ptr"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/config"

	lhv1b1 "github.com/longhorn/longhorn-manager/k8s/pkg/apis/longhorn/v1beta1"
	promv1 "github.com/prometheus-operator/prometheus-operator/pkg/apis/monitoring/v1"
	"github.com/spf13/cobra"

	"github.com/replicatedhq/kurl/pkg/k8sutil"
)

var scaleDownReplicasWaitTime = 5 * time.Minute

const (
	prometheusNamespace          = "monitoring"
	prometheusName               = "k8s"
	prometheusStatefulSetName    = "prometheus-k8s"
	ekcoNamespace                = "kurl"
	ekcoDeploymentName           = "ekc-operator"
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

func NewLonghornRollbackMigrationReplicas(cli CLI) *cobra.Command {
	return &cobra.Command{
		Use:          "rollback-migration-replicas",
		Short:        "Rollback Longhorn Volumes, Deployments, and StetefulSet replicas to their original value.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			logger := cli.Logger()

			logger.Print("Rolling back Longhorn volume replicas to their original value.")
			cli, err := client.New(config.GetConfigOrDie(), client.Options{})
			if err != nil {
				return fmt.Errorf("error creating client: %s", err)
			}
			lhv1b1.AddToScheme(cli.Scheme())
			promv1.AddToScheme(cli.Scheme())

			var l1b1Volumes lhv1b1.VolumeList
			if err := cli.List(cmd.Context(), &l1b1Volumes, client.InNamespace(longhornNamespace)); err != nil {
				return fmt.Errorf("error listing longhorn volumes: %w", err)
			}

			for _, volume := range l1b1Volumes.Items {
				if _, ok := volume.Annotations[pvmigrateScaleDownAnnotation]; !ok {
					logger.Printf("Volume %s has not been scaled down, skipping.", volume.Name)
					continue
				}

				replicas, err := strconv.Atoi(volume.Annotations[pvmigrateScaleDownAnnotation])
				if err != nil {
					return fmt.Errorf("error parsing replica count for volume %s: %w", volume.Name, err)
				}

				logger.Printf("Rolling back volume %s to %d replicas.", volume.Name, replicas)

				// The Longhorn volume could become stale when we update it since volumes can be updated by the Longhorn manager operator
				// resulting in a conflict error.
				// To resolve this, retry the update operation until we no longer get a conflict error.
				retryUpdateErr := retry.RetryOnConflict(retry.DefaultRetry, func() error {
					nsn := types.NamespacedName{Namespace: longhornNamespace, Name: volume.Name}
					if err := cli.Get(cmd.Context(), nsn, &volume); err != nil {
						if errors.IsNotFound(err) {
							logger.Printf("Longhorn volume %s not found. Ignoring since object must have been deleted.", volume.Name)
							return nil
						}
						return fmt.Errorf("Failed to get Longhorn volume %s: %w", volume.Name, err)
					}

					// delete annotation
					delete(volume.Annotations, pvmigrateScaleDownAnnotation)

					// update replicas
					volume.Spec.NumberOfReplicas = replicas
					if err := cli.Update(cmd.Context(), &volume); err != nil {
						return fmt.Errorf("Failed to update Longhorn volume %s: %w", volume.Name, err)
					}
					return nil
				})

				if retryUpdateErr != nil {
					return fmt.Errorf("error rolling back volume %s replicas: %w", volume.Name, err)
				}
			}
			logger.Print("Longhorn volumes have been rolled back to their original replica count.")

			if err := scaleUpPodsUsingLonghorn(context.Background(), logger, cli); err != nil {
				return fmt.Errorf("error scaling up pods using longhorn: %w", err)
			}
			return nil
		},
	}
}

func NewLonghornPrepareForMigration(cli CLI) *cobra.Command {
	return &cobra.Command{
		Use:          "prepare-for-migration",
		Short:        "Prepares Longhorn for migration to a different storage provisioner.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			logger := cli.Logger()

			logger.Print("Preparing Longhorn for migration to a different storage provisioner.")
			cli, err := client.New(config.GetConfigOrDie(), client.Options{})
			if err != nil {
				return fmt.Errorf("error creating client: %s", err)
			}
			lhv1b1.AddToScheme(cli.Scheme())
			promv1.AddToScheme(cli.Scheme())

			var scaledDown bool
			var nodes corev1.NodeList
			if err := cli.List(cmd.Context(), &nodes); err != nil {
				return fmt.Errorf("error listing kubernetes nodes: %s", err)
			} else if len(nodes.Items) == 1 {
				logger.Print("Only one node found, scaling down the number of Longhorn volume replicas to 1.")
				if scaledDown, err = scaleDownReplicas(cmd.Context(), logger, cli); err != nil {
					return fmt.Errorf("error scaling down longhorn replicas: %s", err)
				}
			}

			unhealthy, err := unhealthyVolumes(cmd.Context(), logger, cli)
			if err != nil {
				return fmt.Errorf("error assessing unhealthy volumes: %s", err)
			}

			if len(unhealthy) > 0 {
				logger.Print("The following Longhorn volumes are unhealthy:")
				for _, vol := range unhealthy {
					logger.Printf(" - %s/%s", longhornNamespace, vol)
				}
				return fmt.Errorf("error preparing longhorn for migration: unhealthy volumes")
			}

			unhealthy, err = unhealthyNodes(cmd.Context(), logger, cli)
			if err != nil {
				return fmt.Errorf("error assessing unhealthy Longhorn nodes: %s", err)
			}

			if len(unhealthy) > 0 {
				logger.Print("The following Longhorn nodes are unhealthy:")
				for _, node := range unhealthy {
					logger.Printf(" - %s", node)
				}
				return fmt.Errorf("error preparing longhorn for migration: unhealthy nodes")
			}

			if scaledDown {
				logger.Printf("Storage volumes have been scaled down to 1 replica for the migration.")
				logger.Printf("If necessary, you can scale them back up to the original value with:")
				logger.Printf("")
				logger.Printf("$ kurl longhorn rollback-migration-replicas")
				logger.Printf("")
			}
			logger.Print("All Longhorn volumes and nodes are healthy.")

			if err := scaleDownPodsUsingLonghorn(cmd.Context(), logger, cli); err != nil {
				return fmt.Errorf("error scaling down pods using longhorn volumes: %w", err)
			}
			logger.Print("Environment is ready for the Longhorn migration.")
			return nil
		},
	}
}

// scaleUpPodsUsingLonghorn scales up any deployment or statefulset that has been previously
// scaled down by scaleDownPodsUsingLonghorn. uses the default annotation used by pvmigrate.
func scaleUpPodsUsingLonghorn(ctx context.Context, logger *log.Logger, cli client.Client) error {
	if err := scaleEkco(ctx, logger, cli, 1); err != nil {
		return fmt.Errorf("error scaling ekco operator back up: %w", err)
	}
	if err := scaleUpPrometheus(ctx, cli); err != nil {
		return fmt.Errorf("error scaling prometheus back up: %w", err)
	}

	logger.Print("Scaling up pods using Longhorn volumes.")
	var deps appsv1.DeploymentList
	if err := cli.List(ctx, &deps); err != nil {
		return fmt.Errorf("error listing longhorn deployments: %w", err)
	}
	for _, dep := range deps.Items {
		if _, ok := dep.Annotations[pvmigrateScaleDownAnnotation]; !ok {
			continue
		}
		replicas, err := strconv.Atoi(dep.Annotations[pvmigrateScaleDownAnnotation])
		if err != nil {
			return fmt.Errorf("error parsing replica count for deployment %s/%s: %w", dep.Namespace, dep.Name, err)
		}
		dep.Spec.Replicas = ptr.To(int32(replicas))
		delete(dep.Annotations, pvmigrateScaleDownAnnotation)
		logger.Printf("Scaling up deployment %s/%s", dep.Namespace, dep.Name)
		if err := cli.Update(ctx, &dep); err != nil {
			return fmt.Errorf("error scaling up deployment %s/%s: %w", dep.Namespace, dep.Name, err)
		}
	}

	var sts appsv1.StatefulSetList
	if err := cli.List(ctx, &sts); err != nil {
		return fmt.Errorf("error listing longhorn statefulsets: %w", err)
	}
	for _, st := range sts.Items {
		if _, ok := st.Annotations[pvmigrateScaleDownAnnotation]; !ok {
			continue
		}
		replicas, err := strconv.Atoi(st.Annotations[pvmigrateScaleDownAnnotation])
		if err != nil {
			return fmt.Errorf("error parsing replica count for statefulset %s/%s: %w", st.Namespace, st.Name, err)
		}
		st.Spec.Replicas = ptr.To(int32(replicas))
		delete(st.Annotations, pvmigrateScaleDownAnnotation)
		logger.Printf("Scaling up statefulset %s/%s", st.Namespace, st.Name)
		if err := cli.Update(ctx, &st); err != nil {
			return fmt.Errorf("error scaling up statefulset %s/%s: %w", st.Namespace, st.Name, err)
		}
	}

	logger.Print("Pods using Longhorn volumes have been scaled up.")
	return nil
}

// scaleDownPodsUsingLonghorn scales down all pods using Longhorn volumes.
func scaleDownPodsUsingLonghorn(ctx context.Context, logger *log.Logger, cli client.Client) error {
	logger.Print("Scaling down pods using Longhorn volumes.")
	if err := scaleEkco(ctx, logger, cli, 0); err != nil {
		return fmt.Errorf("error scaling down ekco operator: %w", err)
	}
	if err := scaleDownPrometheus(ctx, logger, cli); err != nil {
		return fmt.Errorf("error scaling down prometheus: %w", err)
	}
	objects, err := getObjectsUsingLonghorn(ctx, cli)
	if err != nil {
		return fmt.Errorf("error getting objects using longhorn: %w", err)
	}
	for _, obj := range objects {
		if err := scaleDownObject(ctx, logger, cli, obj); err != nil {
			return err
		}
	}
	logger.Print("Pods using Longhorn volumes have been scaled down.")
	return nil
}

func isPrometheusInstalled(ctx context.Context, cli client.Client) (bool, error) {
	nsn := types.NamespacedName{Name: prometheusNamespace}
	if err := cli.Get(ctx, nsn, &corev1.Namespace{}); err != nil {
		if errors.IsNotFound(err) {
			return false, nil
		}
		return false, fmt.Errorf("error getting prometheus namespace: %w", err)
	}
	return true, nil
}

// scaleDownPrometheus scales down prometheus.
func scaleDownPrometheus(ctx context.Context, logger *log.Logger, cli client.Client) error {
	if installed, err := isPrometheusInstalled(ctx, cli); err != nil {
		return fmt.Errorf("error scaling down prometheus: %w", err)
	} else if !installed {
		return nil
	}

	nsn := types.NamespacedName{Namespace: prometheusNamespace, Name: prometheusName}
	var prometheus promv1.Prometheus
	if err := cli.Get(ctx, nsn, &prometheus); err != nil {
		if errors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("error getting prometheus: %w", err)
	}

	patch := map[string]interface{}{
		"spec": map[string]interface{}{
			"replicas": 0,
		},
	}
	if _, ok := prometheus.Annotations[pvmigrateScaleDownAnnotation]; !ok {
		promReplicas := int32(0)
		if prometheus.Spec.Replicas != nil {
			promReplicas = *prometheus.Spec.Replicas
		}
		patch["metadata"] = map[string]interface{}{
			"annotations": map[string]string{
				pvmigrateScaleDownAnnotation: fmt.Sprintf("%d", promReplicas),
			},
		}
	}

	rawPatch, err := json.Marshal(patch)
	if err != nil {
		return fmt.Errorf("error creating prometheus patch: %w", err)
	}
	if err := cli.Patch(ctx, &prometheus, client.RawPatch(types.MergePatchType, rawPatch)); err != nil {
		return fmt.Errorf("error scaling prometheus: %w", err)
	}

	var st appsv1.StatefulSet
	if err := wait.PollUntilContextTimeout(ctx, 3*time.Second, 5*time.Minute, true, func(ctx2 context.Context) (bool, error) {
		nsn = types.NamespacedName{Namespace: prometheusNamespace, Name: prometheusStatefulSetName}
		if err := cli.Get(ctx2, nsn, &st); err != nil {
			return false, fmt.Errorf("error getting prometheus statefulset: %w", err)
		}
		return st.Status.Replicas == 0 && st.Status.UpdatedReplicas == 0, nil
	}); err != nil {
		return fmt.Errorf("error waiting for prometheus statefulset to scale: %w", err)
	}

	logger.Print("Waiting for prometheus StatefulSet to scale down.")
	selector := labels.SelectorFromSet(st.Spec.Selector.MatchLabels)
	if err := waitForPodsToBeScaledDown(ctx, logger, cli, ekcoNamespace, selector); err != nil {
		return fmt.Errorf("error waiting for prometheus to scale down: %w", err)
	}
	return nil
}

// scaleUpPrometheus scales up prometheus.
func scaleUpPrometheus(ctx context.Context, cli client.Client) error {
	if installed, err := isPrometheusInstalled(ctx, cli); err != nil {
		return fmt.Errorf("error scaling down prometheus: %w", err)
	} else if !installed {
		return nil
	}

	nsn := types.NamespacedName{Namespace: prometheusNamespace, Name: prometheusName}
	var prometheus promv1.Prometheus
	if err := cli.Get(ctx, nsn, &prometheus); err != nil {
		if errors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("error getting prometheus: %w", err)
	}
	replicasStr, ok := prometheus.Annotations[pvmigrateScaleDownAnnotation]
	if !ok {
		return fmt.Errorf("error reading original replicas from the prometheus annotation: not found")
	}
	origReplicas, err := strconv.Atoi(replicasStr)
	if err != nil {
		return fmt.Errorf("error converting replicas annotation to integer: %w", err)
	}
	patch := map[string]interface{}{
		"metadata": map[string]interface{}{
			"annotations": map[string]interface{}{
				pvmigrateScaleDownAnnotation: nil,
			},
		},
		"spec": map[string]interface{}{
			"replicas": origReplicas,
		},
	}
	rawPatch, err := json.Marshal(patch)
	if err != nil {
		return fmt.Errorf("error creating prometheus patch: %w", err)
	}
	if err := cli.Patch(ctx, &prometheus, client.RawPatch(types.MergePatchType, rawPatch)); err != nil {
		return fmt.Errorf("error scaling prometheus: %w", err)
	}
	return nil
}

// scaleEkco scales ekco operator to the number of provided replicas.
func scaleEkco(ctx context.Context, logger *log.Logger, cli client.Client, replicas int32) error {
	nsn := types.NamespacedName{Namespace: ekcoNamespace, Name: ekcoDeploymentName}
	var dep appsv1.Deployment
	if err := cli.Get(ctx, nsn, &dep); err != nil {
		if errors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("error reading ekco deployment: %w", err)
	}
	dep.Spec.Replicas = &replicas
	if err := cli.Update(ctx, &dep); err != nil {
		return fmt.Errorf("error scaling ekco deployment: %w", err)
	}
	if replicas != 0 {
		return nil
	}
	logger.Print("Waiting for ekco operator to scale down.")
	if err := waitForPodsToBeScaledDown(
		ctx, logger, cli, ekcoNamespace, labels.SelectorFromSet(dep.Spec.Selector.MatchLabels),
	); err != nil {
		return fmt.Errorf("error waiting for ekco operator to scale down: %w", err)
	}
	return nil
}

// waitForPodsToBeScaledDown waits for all pods using matching the provided selector to disappear in the provided
// namespace.
func waitForPodsToBeScaledDown(ctx context.Context, logger *log.Logger, cli client.Client, ns string, sel labels.Selector) error {
	return wait.PollUntilContextTimeout(ctx, 3*time.Second, 5*time.Minute, true, func(ctx2 context.Context) (bool, error) {
		var pods corev1.PodList
		opts := []client.ListOption{
			client.InNamespace(ns),
			client.MatchingLabelsSelector{Selector: sel},
		}
		if err := cli.List(ctx2, &pods, opts...); err != nil {
			return false, fmt.Errorf("error listing pods: %w", err)
		}
		if len(pods.Items) > 0 {
			logger.Printf("%d pods found, waiting for them to be scaled down.", len(pods.Items))
			return false, nil
		}
		return true, nil
	})
}

// scaleDownObject scales down a deployment or a statefulset to 0 replicas.
func scaleDownObject(ctx context.Context, logger *log.Logger, cli client.Client, obj client.Object) error {
	kind := strings.ToLower(fmt.Sprintf("%T", obj))
	logger.Printf("Scaling down %s %s/%s", kind, obj.GetNamespace(), obj.GetName())

	var selector labels.Selector
	var replicas *int32
	switch concrete := obj.(type) {
	case *appsv1.Deployment:
		replicas = concrete.Spec.Replicas
		concrete.Spec.Replicas = ptr.To(int32(0))
		selector = labels.SelectorFromSet(concrete.Spec.Selector.MatchLabels)
	case *appsv1.StatefulSet:
		replicas = concrete.Spec.Replicas
		concrete.Spec.Replicas = ptr.To(int32(0))
		selector = labels.SelectorFromSet(concrete.Spec.Selector.MatchLabels)
	default:
		return fmt.Errorf("unsupported object type %T", obj)
	}

	if replicas == nil {
		replicas = ptr.To(int32(0))
	}

	annotations := obj.GetAnnotations()
	if annotations == nil {
		annotations = map[string]string{}
	}
	if _, ok := annotations[pvmigrateScaleDownAnnotation]; !ok {
		annotations[pvmigrateScaleDownAnnotation] = fmt.Sprintf("%d", *replicas)
		obj.SetAnnotations(annotations)
	}

	if err := cli.Update(ctx, obj); err != nil {
		return fmt.Errorf("error scaling down %s %s/%s: %w", kind, obj.GetNamespace(), obj.GetName(), err)
	}
	if err := waitForPodsToBeScaledDown(ctx, logger, cli, obj.GetNamespace(), selector); err != nil {
		return fmt.Errorf("error waiting for %s %s/%s to scale down: %w", kind, obj.GetNamespace(), obj.GetName(), err)
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
	var objects []client.Object
	controllers := make(map[string]client.Object)
	for _, pod := range pods {
		ctrl := metav1.GetControllerOf(&pod)
		if ctrl == nil {
			return nil, fmt.Errorf("pod %s/%s has no owners and can't be migrated", pod.Name, pod.Namespace)
		}
		uid, obj, err := getOwnerObject(ctx, cli, pod.Namespace, *ctrl)
		if err != nil {
			return nil, fmt.Errorf("error getting owner object for pod %s/%s: %w", pod.Namespace, pod.Name, err)
		}
		controllers[*uid] = obj
	}

	// convert map to slice
	for _, obj := range controllers {
		objects = append(objects, obj)
	}

	return objects, nil
}

// getOwnerObject returns the object referred by the provided owner reference. Only deployments, statefulsets,
// and replicasets are supported (as those are the only types supported by pvmigrate).
func getOwnerObject(ctx context.Context, cli client.Client, namespace string, owner metav1.OwnerReference) (*string, client.Object, error) {
	switch owner.Kind {
	case "StatefulSet":
		nsn := types.NamespacedName{Namespace: namespace, Name: owner.Name}
		var sset appsv1.StatefulSet
		if err := cli.Get(ctx, nsn, &sset); err != nil {
			return nil, nil, fmt.Errorf("error getting statefulset %s: %w", nsn, err)
		}
		return (*string)(&sset.UID), &sset, nil
	case "ReplicaSet":
		nsn := types.NamespacedName{Namespace: namespace, Name: owner.Name}
		var rset appsv1.ReplicaSet
		if err := cli.Get(ctx, nsn, &rset); err != nil {
			return nil, nil, fmt.Errorf("error getting replicaset %s: %w", nsn, err)
		}
		ctrl := metav1.GetControllerOf(&rset)
		if ctrl == nil {
			return nil, nil, fmt.Errorf("no owner found for replicaset %s/%s", owner.Name, namespace)
		} else if ctrl.Kind != "Deployment" {
			return nil, nil, fmt.Errorf(
				"expected replicaset %s in %s to have a deployment as owner, found %s instead",
				owner.Name, namespace, ctrl.Kind,
			)
		}
		nsn = types.NamespacedName{Namespace: namespace, Name: ctrl.Name}
		var deployment appsv1.Deployment
		if err := cli.Get(ctx, nsn, &deployment); err != nil {
			return nil, nil, fmt.Errorf("error getting deployment %s: %w", nsn, err)
		}
		return (*string)(&deployment.UID), &deployment, nil
	default:
		return nil, nil, fmt.Errorf(
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
func scaleDownReplicas(ctx context.Context, logger *log.Logger, cli client.Client) (bool, error) {
	var l1b1Volumes lhv1b1.VolumeList
	if err := cli.List(ctx, &l1b1Volumes, client.InNamespace(longhornNamespace)); err != nil {
		return false, fmt.Errorf("error listing longhorn volumes: %w", err)
	}

	var volumesToScale []lhv1b1.Volume
	for _, volume := range l1b1Volumes.Items {
		if volume.Spec.NumberOfReplicas == 1 {
			logger.Printf("Volume %s already has 1 replica, skipping.", volume.Name)
			continue
		}
		volumesToScale = append(volumesToScale, volume)
	}

	if len(volumesToScale) == 0 {
		return false, nil
	}

	for _, volume := range volumesToScale {
		logger.Printf("Scaling down replicas for volume %s.", volume.Name)
		for {
			nsn := types.NamespacedName{Namespace: longhornNamespace, Name: volume.Name}
			var updatedVolume lhv1b1.Volume
			if err := cli.Get(ctx, nsn, &updatedVolume); err != nil {
				return false, fmt.Errorf("error getting volume %s: %w", volume.Name, err)
			}

			if updatedVolume.Annotations == nil {
				updatedVolume.Annotations = map[string]string{}
			}
			if _, ok := updatedVolume.Annotations[pvmigrateScaleDownAnnotation]; !ok {
				updatedVolume.Annotations[pvmigrateScaleDownAnnotation] = strconv.Itoa(updatedVolume.Spec.NumberOfReplicas)
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

	logger.Printf("Waiting %v for Longhorn volume replicas to scale down.", scaleDownReplicasWaitTime)
	time.Sleep(scaleDownReplicasWaitTime)
	return true, nil
}

// unhealthyVolumes returns a list of attached volumes that are not in a healthy state.
func unhealthyVolumes(ctx context.Context, logger *log.Logger, cli client.Client) ([]string, error) {
	var volumes lhv1b1.VolumeList
	if err := cli.List(ctx, &volumes, client.InNamespace(longhornNamespace)); err != nil {
		return nil, fmt.Errorf("error listing volumes: %w", err)
	}
	var result []string
	for _, volume := range volumes.Items {
		logger.Printf("Checking health of volume %s.", volume.Name)
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
func unhealthyNodes(ctx context.Context, logger *log.Logger, cli client.Client) ([]string, error) {
	var longhornNodes lhv1b1.NodeList
	if err := cli.List(ctx, &longhornNodes); err != nil {
		return nil, fmt.Errorf("error listing longhorn nodes: %w", err)
	}
	var result []string
	for _, node := range longhornNodes.Items {
		logger.Printf("Checking health of node %s.", node.Name)
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
