package rook

import (
	"context"
	"fmt"
	"io"
	"log"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/pkg/k8sutil"
	"github.com/replicatedhq/kurl/pkg/rook/static"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

const (
	desiredScaleAnnotation = "kurl.sh/rook-flexvolume-to-csi-desired-scale"
)

// FlexvolumeToCSIOpts are options for the FlexvolumeToCSI function
type FlexvolumeToCSIOpts struct {
	// SourceStorageClass is the name of the storage class to migrate from
	SourceStorageClass string
	// DestinationStorageClass is the name of the storage class to migrate to
	DestinationStorageClass string
}

// Validate will validate options to the FlexvolumeToCSI function and return an error if any are
// invalid
func (o FlexvolumeToCSIOpts) Validate() error {
	if o.SourceStorageClass == "" {
		return errors.New("source storage class is required")
	}
	if o.DestinationStorageClass == "" {
		return errors.New("destination storage class is required")
	}
	return nil
}

// FlexvolumeToCSI will migrate from a Rook Flex volumes storage class a Ceph-CSI volumes storage
// class
func FlexvolumeToCSI(ctx context.Context, clientset kubernetes.Interface, clientConfig *rest.Config, logger *log.Logger, opts FlexvolumeToCSIOpts) error {
	err := opts.Validate()
	if err != nil {
		return err
	}

	_, err = exec.LookPath("kubectl")
	if err != nil {
		return errors.Wrap(err, "which kubectl")
	}

	logger.Printf("Scaling down statefulsets and deployments using storage class %s ...", opts.SourceStorageClass)
	pvcs, err := listPVCsByStorageClass(ctx, clientset, opts.SourceStorageClass)
	if err != nil {
		return errors.Wrap(err, "list pvcs")
	}

	for _, pvc := range pvcs {
		pods, err := listPodsMountingPVC(ctx, clientset, pvc.Namespace, pvc.Name)
		if err != nil {
			return errors.Wrapf(err, "list pods mounting pvc %s/%s", pvc.Namespace, pvc.Name)
		}
		for _, pod := range pods {
			logger.Printf("Scaling down pod %s/%s owner ...", pod.Namespace, pod.Name)
			err := scaleDownPodOwner(ctx, clientset, pod)
			if err != nil {
				return errors.Wrapf(err, "scale down pod %s/%s owner", pod.Namespace, pod.Name)
			}
			logger.Println("Scaled down pod owner")
		}
	}
	logger.Println("Scaled down statefulsets and deployments")

	logger.Printf("Running ceph/pv-migrator from %s to %s ...", opts.SourceStorageClass, opts.DestinationStorageClass)
	// NOTE: this is a destructive migration and if it fails in the middle it will be hard to recover from
	err = runBinPVMigrator(ctx, logger.Writer(), clientset, clientConfig, opts.SourceStorageClass, opts.DestinationStorageClass)
	if err != nil {
		return errors.Wrap(err, "run ceph/pv-migrator")
	}
	logger.Println("Ran ceph/pv-migrator")

	logger.Printf("Scaling back statefulsets and replicasets using storage class %s ...", opts.SourceStorageClass)
	pvcNamespaces := make(map[string]struct{})
	for _, pvc := range pvcs {
		pvcNamespaces[pvc.Namespace] = struct{}{}
	}

	for namespace := range pvcNamespaces {
		logger.Printf("Scaling back statefulsets in namespace %s ...", namespace)
		err := scaleBackStatefulSetsByNamespace(ctx, clientset, namespace)
		if err != nil {
			return errors.Wrapf(err, "scale back statefulsets in namespace %s", namespace)
		}
		logger.Println("Scaled back statefulsets")

		logger.Printf("Scaling back replicasets in namespace %s ...", namespace)
		err = scaleBackReplicaSetsByNamespace(ctx, clientset, namespace)
		if err != nil {
			return errors.Wrapf(err, "scale back replicasets in namespace %s", namespace)
		}
		logger.Println("Scaled back replicasets")
	}
	logger.Println("Scaled back statefulsets and replicasets")

	return nil
}

func runBinPVMigrator(ctx context.Context, w io.Writer, clientset kubernetes.Interface, clientConfig *rest.Config, sourceSC, destSC string) error {
	// NOTE: this deployment uses image rook/ceph:v1.7.11 and will only work for that specific Rook
	// add-on version
	out, err := k8sutil.KubectlApply(ctx, static.FlexMigrator)
	if out != nil {
		fmt.Fprintln(w, string(out))
	}
	if err != nil {
		return errors.Wrap(err, "kubectl apply flex migrator")
	}

	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	err = k8sutil.WaitForDeploymentReady(ctx, clientset, "rook-ceph", "rook-ceph-migrator")
	if err != nil {
		return errors.Wrap(err, "wait for rook-ceph-migrator deployment")
	}

	pods, err := k8sutil.ListPodsBySelector(ctx, clientset, "rook-ceph", "app=rook-ceph-migrator")
	if err != nil {
		return errors.Wrap(err, "list pods")
	}
	if len(pods.Items) == 0 {
		return errors.New("no pods found for rook-ceph-migrator deployment")
	}
	pod := pods.Items[0]

	if !k8sutil.IsPodReady(pod) {
		return errors.New("rook-ceph-migrator pod is not ready")
	}

	command := []string{
		"pv-migrator",
		"--source-sc", sourceSC,
		"--destination-sc", destSC,
	}

	opts := k8sutil.ExecOptions{
		CoreClient: clientset.CoreV1(),
		Config:     clientConfig,
		Command:    command,
		StreamOptions: k8sutil.StreamOptions{
			Namespace:     "rook-ceph",
			PodName:       pod.Name,
			ContainerName: "rook-ceph-migrator",
			Out:           w,
			Err:           w,
		},
	}
	exitCode, err := k8sutil.ExecContainer(ctx, opts, nil)
	if err != nil {
		return errors.Wrap(err, "exec command in pod")
	} else if exitCode != 0 {
		return errors.Errorf("command returned non-zero exit code %d", exitCode)
	}

	return nil
}

func newDesiredScaleAnnotationPatch(replicas int32) []byte {
	return []byte(fmt.Sprintf(
		`[{"op": "replace", "path": "/metadata/annotations/%s", "value": "%d"}]`,
		strings.Replace(desiredScaleAnnotation, "/", "~1", -1),
		replicas,
	))
}

func newRemoveDesiredScaleAnnotationPatch() []byte {
	return []byte(fmt.Sprintf(
		`[{"op": "remove", "path": "/metadata/annotations/%s"}]`,
		strings.Replace(desiredScaleAnnotation, "/", "~1", -1),
	))
}

func newSpecReplicasPatch(replicas int32) []byte {
	return []byte(fmt.Sprintf(
		`[{"op": "replace", "path": "/spec/replicas", "value": %d}]`,
		replicas,
	))
}

func scaleDownPodOwner(ctx context.Context, clientset kubernetes.Interface, pod corev1.Pod) error {
	if len(pod.OwnerReferences) == 0 {
		return errors.New("pod not owned by any object")
	}
	for _, ref := range pod.OwnerReferences {
		switch ref.Kind {
		case "StatefulSet":
			obj, err := clientset.AppsV1().StatefulSets(pod.Namespace).Get(ctx, ref.Name, metav1.GetOptions{})
			if err != nil {
				return errors.Wrapf(err, "get statefulset %s/%s", pod.Namespace, ref.Name)
			}
			err = scaleDownStatefulSet(ctx, clientset, *obj)
			if err != nil {
				return errors.Wrapf(err, "scale down statefulset %s/%s", pod.Namespace, ref.Name)
			}
		case "ReplicaSet":
			obj, err := clientset.AppsV1().ReplicaSets(pod.Namespace).Get(ctx, ref.Name, metav1.GetOptions{})
			if err != nil {
				return errors.Wrapf(err, "get replicaset %s/%s", pod.Namespace, ref.Name)
			}
			err = scaleDownReplicaSet(ctx, clientset, *obj)
			if err != nil {
				return errors.Wrapf(err, "scale down replicaset %s/%s", pod.Namespace, ref.Name)
			}
		default:
			return errors.Errorf("cannot scale down kind %s", ref.Kind)
		}
	}
	return nil
}

func scaleDownStatefulSet(ctx context.Context, clientset kubernetes.Interface, obj appsv1.StatefulSet) error {
	replicas := int32(1)
	if obj.Spec.Replicas != nil {
		replicas = *obj.Spec.Replicas
	}
	_, err := clientset.AppsV1().StatefulSets(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newDesiredScaleAnnotationPatch(replicas), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch annotation")
	}
	_, err = clientset.AppsV1().StatefulSets(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newSpecReplicasPatch(0), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch replicas")
	}
	return nil
}

func scaleDownReplicaSet(ctx context.Context, clientset kubernetes.Interface, obj appsv1.ReplicaSet) error {
	replicas := int32(1)
	if obj.Spec.Replicas != nil {
		replicas = *obj.Spec.Replicas
	}
	_, err := clientset.AppsV1().ReplicaSets(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newDesiredScaleAnnotationPatch(replicas), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch annotation")
	}
	_, err = clientset.AppsV1().ReplicaSets(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newSpecReplicasPatch(0), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch replicas")
	}
	return nil
}

func scaleBackStatefulSetsByNamespace(ctx context.Context, clientset kubernetes.Interface, namespace string) error {
	objs, err := clientset.AppsV1().StatefulSets(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "list statefulsets")
	}
	for _, obj := range objs.Items {
		err := scaleBackStatefulSet(ctx, clientset, obj)
		if err != nil {
			return errors.Wrapf(err, "scale back statefulset %s/%s", obj.GetNamespace(), obj.GetName())
		}
	}
	return nil
}

func scaleBackStatefulSet(ctx context.Context, clientset kubernetes.Interface, obj appsv1.StatefulSet) error {
	desiredScale, ok := obj.GetAnnotations()[desiredScaleAnnotation]
	if !ok {
		return nil
	}
	replicas, err := strconv.Atoi(desiredScale)
	if err != nil {
		return errors.Wrapf(err, "parse desired scale annotation")
	}
	_, err = clientset.AppsV1().StatefulSets(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newSpecReplicasPatch(int32(replicas)), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch replicas")
	}
	_, err = clientset.AppsV1().StatefulSets(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newRemoveDesiredScaleAnnotationPatch(), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch annotation")
	}
	return nil
}

func scaleBackReplicaSetsByNamespace(ctx context.Context, clientset kubernetes.Interface, namespace string) error {
	objs, err := clientset.AppsV1().ReplicaSets(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "list replicasets")
	}
	for _, obj := range objs.Items {
		err := scaleBackReplicaSet(ctx, clientset, obj)
		if err != nil {
			return errors.Wrapf(err, "scale back replicaset %s/%s", obj.GetNamespace(), obj.GetName())
		}
	}
	return nil
}

func scaleBackReplicaSet(ctx context.Context, clientset kubernetes.Interface, obj appsv1.ReplicaSet) error {
	desiredScale, ok := obj.GetAnnotations()[desiredScaleAnnotation]
	if !ok {
		return nil
	}
	replicas, err := strconv.Atoi(desiredScale)
	if err != nil {
		return errors.Wrapf(err, "parse desired scale annotation")
	}
	_, err = clientset.AppsV1().ReplicaSets(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newSpecReplicasPatch(int32(replicas)), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch replicas")
	}
	_, err = clientset.AppsV1().ReplicaSets(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newRemoveDesiredScaleAnnotationPatch(), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch annotation")
	}
	return nil
}

func listPVCsByStorageClass(ctx context.Context, clientset kubernetes.Interface, name string) ([]corev1.PersistentVolumeClaim, error) {
	res := []corev1.PersistentVolumeClaim{}
	ns, err := clientset.CoreV1().Namespaces().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, errors.Wrap(err, "list namespaces")
	}
	for _, n := range ns.Items {
		pvcs, err := clientset.CoreV1().PersistentVolumeClaims(n.Name).List(ctx, metav1.ListOptions{})
		if err != nil {
			return nil, errors.Wrapf(err, "list pvcs in namespace %s", n.Name)
		}
		for _, pvc := range pvcs.Items {
			if pvc.Spec.StorageClassName != nil && *pvc.Spec.StorageClassName == name {
				res = append(res, pvc)
			}
		}
	}
	return res, nil
}

func listPodsMountingPVC(ctx context.Context, clientset kubernetes.Interface, namespace, name string) ([]corev1.Pod, error) {
	res := []corev1.Pod{}
	pods, err := clientset.CoreV1().Pods(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, errors.Wrap(err, "list pods")
	}
	for _, pod := range pods.Items {
		if k8sutil.PodHasPVC(pod, namespace, name) {
			res = append(res, pod)
		}
	}
	return res, nil
}
