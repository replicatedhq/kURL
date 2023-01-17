package rook

import (
	"context"
	"fmt"
	"html/template"
	"io/fs"
	"log"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/pkg/k8sutil"
	"github.com/replicatedhq/kurl/pkg/rook/static/flexmigrator"
	"github.com/ricardomaraschini/plumber"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/kustomize/kyaml/filesys"
)

const (
	rookCephNamespace                       = "rook-ceph"
	rookCephMigratorDeploymentName          = "rook-ceph-migrator"
	rookCephMigratorPodContainerName        = "rook-ceph-migrator"
	rookCephMigratorDeploymentLabelSelector = "app=rook-ceph-migrator"

	desiredScaleAnnotation = "kurl.sh/rook-flexvolume-to-csi-desired-scale"
)

// FlexvolumeToCSIOpts are options for the FlexvolumeToCSI function
type FlexvolumeToCSIOpts struct {
	// SourceStorageClass is the name of the storage class to migrate from
	SourceStorageClass string
	// DestinationStorageClass is the name of the storage class to migrate to
	DestinationStorageClass string
	// PVMigratorBinPath is the path to the ceph/pv-migrator binary
	PVMigratorBinPath string
	// CephMigratorImage is the image to use for the ceph/pv-migrator container
	CephMigratorImage string
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
	if o.PVMigratorBinPath == "" {
		return errors.New("pv migrator binary path is required")
	}
	if o.CephMigratorImage == "" {
		return errors.New("ceph migrator image is required")
	}
	if _, err := exec.LookPath(o.PVMigratorBinPath); err != nil {
		return errors.Wrapf(err, "which %s", o.PVMigratorBinPath)
	}
	return nil
}

// FlexvolumeToCSI will migrate from a Rook Flex volumes storage class to a Ceph-CSI volumes
// storage
func FlexvolumeToCSI(ctx context.Context, logger *log.Logger, clientset kubernetes.Interface, clientConfig *rest.Config, opts FlexvolumeToCSIOpts) error {
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
	err = runBinPVMigrator(ctx, logger, clientset, clientConfig, opts)
	if err != nil {
		return errors.Wrap(err, "run ceph/pv-migrator")
	}
	logger.Println("Ran ceph/pv-migrator")

	logger.Printf("Scaling back statefulsets and deployments using storage class %s ...", opts.SourceStorageClass)
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

		logger.Printf("Scaling back deployments in namespace %s ...", namespace)
		err = scaleBackDeploymentsByNamespace(ctx, clientset, namespace)
		if err != nil {
			return errors.Wrapf(err, "scale back deployments in namespace %s", namespace)
		}
		logger.Println("Scaled back deployments")
	}
	logger.Println("Scaled back statefulsets and deployments")

	return nil
}

func runBinPVMigrator(ctx context.Context, logger *log.Logger, clientset kubernetes.Interface, clientConfig *rest.Config, opts FlexvolumeToCSIOpts) error {
	cli, err := client.New(clientConfig, client.Options{})
	if err != nil {
		return errors.Wrap(err, "create kubernetes client")
	}

	err = runFlexMigrator(ctx, logger, cli, opts)
	if err != nil {
		return errors.Wrap(err, "run flex migrator")
	}

	defer func() {
		err := deleteBinPVMigratorResources(context.Background(), logger)
		if err != nil {
			logger.Printf("Failed to delete flex migrator resources: %v", err)
		}
	}()

	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	logger.Println("Waiting for rook-ceph-migrator deployment to be ready ...")
	err = k8sutil.WaitForDeploymentReady(ctx, clientset, rookCephNamespace, rookCephMigratorDeploymentName)
	if err != nil {
		return errors.Wrap(err, "wait for rook-ceph-migrator deployment")
	}
	logger.Println("Rook-ceph-migrator deployment is ready")

	pods, err := k8sutil.ListPodsBySelector(ctx, clientset, rookCephNamespace, rookCephMigratorDeploymentLabelSelector)
	if err != nil {
		return errors.Wrap(err, "list pods")
	}
	if len(pods.Items) == 0 {
		return errors.New("no pods found for rook-ceph-migrator deployment")
	}
	pod := pods.Items[0]

	logger.Printf("Waiting for %s/%s pod to be ready ...", pod.Namespace, pod.Name)
	err = k8sutil.WaitForPodReady(ctx, clientset, pod.Namespace, pod.Name)
	if err != nil {
		return errors.Wrap(err, "wait for rook-ceph-migrator deployment")
	}
	logger.Printf("%s/%s pod is ready", pod.Namespace, pod.Name)

	command := []string{
		"pv-migrator",
		"--source-sc", opts.SourceStorageClass,
		"--destination-sc", opts.DestinationStorageClass,
	}

	execOpts := k8sutil.ExecOptions{
		CoreClient: clientset.CoreV1(),
		Config:     clientConfig,
		Command:    command,
		StreamOptions: k8sutil.StreamOptions{
			Namespace:     rookCephNamespace,
			PodName:       pod.Name,
			ContainerName: rookCephMigratorPodContainerName,
			Out:           logger.Writer(),
			Err:           logger.Writer(),
		},
	}

	logger.Printf("Running command %q in %s/%s pod ...", command, pod.Namespace, pod.Name)
	exitCode, err := k8sutil.ExecContainer(ctx, execOpts, nil)
	if err != nil {
		return errors.Wrap(err, "exec command in pod")
	} else if exitCode != 0 {
		return errors.Errorf("command returned non-zero exit code %d", exitCode)
	}
	logger.Println("Command pod completed successfully")

	return nil
}

func runFlexMigrator(ctx context.Context, logger *log.Logger, cli client.Client, opts FlexvolumeToCSIOpts) error {
	options := []plumber.Option{
		plumber.WithFSMutator(func(ctx context.Context, fs filesys.FileSystem) error {
			return generateFlexMigratorPatch(fs, opts)
		}),
	}

	logger.Println("Applying flex migrator ...")
	err := k8sutil.KubectlApply(ctx, cli, flexmigrator.FS, "overlays/kurl", options...)
	if err != nil {
		return errors.Wrap(err, "kubectl apply flex migrator")
	}
	logger.Println("Applied flex migrator")

	return nil
}

func deleteBinPVMigratorResources(ctx context.Context, logger *log.Logger) error {
	logger.Println("Deleting flex migrator ...")
	b, err := fs.ReadFile(flexmigrator.FS, "kustomize/base/flex-migrator.yaml")
	if err != nil {
		return errors.Wrap(err, "read flex migrator kustomize")
	}
	out, err := k8sutil.KubectlDelete(ctx, b, "--ignore-not-found=true")
	if out != nil {
		logger.Println((strings.TrimSpace(string(out))))
	}
	if err != nil {
		return errors.Wrap(err, "kubectl delete flex migrator")
	}
	logger.Println("Deleted flex migrator")
	return nil
}

func generateFlexMigratorPatch(fs filesys.FileSystem, opts FlexvolumeToCSIOpts) error {
	file := "kustomize/overlays/kurl/flex-migrator.patch.yaml"
	b, err := fs.ReadFile(file)
	if err != nil {
		return errors.Wrap(err, "read flex migrator patch")
	}
	data := map[string]string{
		"PVMigratorBinPath":     opts.PVMigratorBinPath,
		"RookCephMigratorImage": opts.CephMigratorImage,
	}
	tmpl, err := template.New("flex-migrator-patch").Parse(string(b))
	if err != nil {
		return errors.Wrap(err, "parse flex migrator patch")
	}
	f, err := fs.Open(file)
	if err != nil {
		return errors.Wrap(err, "open flex migrator patch")
	}
	defer f.Close()
	err = tmpl.Execute(f, data)
	if err != nil {
		return errors.Wrap(err, "execute flex migrator patch")
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
	if len(pod.OwnerReferences) != 1 {
		return fmt.Errorf("expected 1 owner for pod, found %d instead", len(pod.OwnerReferences))
	}
	ref := pod.OwnerReferences[0]

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
		if len(obj.OwnerReferences) != 1 {
			return fmt.Errorf("expected 1 owner for replicaset %s, found %d instead", ref.Name, len(obj.OwnerReferences))
		}
		ref := obj.OwnerReferences[0]
		if ref.Kind != "Deployment" {
			return fmt.Errorf("expected owner for replicaset %s to be a deployment, found %s of kind %s instead", obj.Name, ref.Name, ref.Kind)
		}
		dep, err := clientset.AppsV1().Deployments(pod.Namespace).Get(ctx, ref.Name, metav1.GetOptions{})
		if err != nil {
			return errors.Wrapf(err, "get deployment %s/%s", pod.Namespace, ref.Name)
		}
		err = scaleDownDeployment(ctx, clientset, *dep)
		if err != nil {
			return errors.Wrapf(err, "scale down deployment %s/%s", pod.Namespace, ref.Name)
		}
	default:
		return errors.Errorf("cannot scale down kind %s", ref.Kind)
	}

	return nil
}

func scaleDownStatefulSet(ctx context.Context, clientset kubernetes.Interface, obj appsv1.StatefulSet) error {
	replicas := int32(1)
	if obj.Spec.Replicas != nil {
		replicas = *obj.Spec.Replicas
	}
	// check if the resource is already scaled down as it could have multiple replicas
	if replicas == 0 {
		return nil
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

func scaleDownDeployment(ctx context.Context, clientset kubernetes.Interface, obj appsv1.Deployment) error {
	replicas := int32(1)
	if obj.Spec.Replicas != nil {
		replicas = *obj.Spec.Replicas
	}
	// check if the resource is already scaled down as it could have multiple replicas
	// this is unlikely as deployments with multiple replicas are not likely to have mounted persistent volumes
	if replicas == 0 {
		return nil
	}
	_, err := clientset.AppsV1().Deployments(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newDesiredScaleAnnotationPatch(replicas), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch annotation")
	}
	_, err = clientset.AppsV1().Deployments(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newSpecReplicasPatch(0), metav1.PatchOptions{})
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

func scaleBackDeploymentsByNamespace(ctx context.Context, clientset kubernetes.Interface, namespace string) error {
	objs, err := clientset.AppsV1().Deployments(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "list deployments")
	}
	for _, obj := range objs.Items {
		err := scaleBackDeployment(ctx, clientset, obj)
		if err != nil {
			return errors.Wrapf(err, "scale back deployment %s/%s", obj.GetNamespace(), obj.GetName())
		}
	}
	return nil
}

func scaleBackDeployment(ctx context.Context, clientset kubernetes.Interface, obj appsv1.Deployment) error {
	desiredScale, ok := obj.GetAnnotations()[desiredScaleAnnotation]
	if !ok {
		return nil
	}
	replicas, err := strconv.Atoi(desiredScale)
	if err != nil {
		return errors.Wrapf(err, "parse desired scale annotation")
	}
	_, err = clientset.AppsV1().Deployments(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newSpecReplicasPatch(int32(replicas)), metav1.PatchOptions{})
	if err != nil {
		return errors.Wrap(err, "patch replicas")
	}
	_, err = clientset.AppsV1().Deployments(obj.GetNamespace()).Patch(ctx, obj.GetName(), types.JSONPatchType, newRemoveDesiredScaleAnnotationPatch(), metav1.PatchOptions{})
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
