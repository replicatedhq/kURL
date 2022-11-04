package k8sutil

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// PVSByStorageClass returns a map of persistent volumes using the provided storage class name.
// returned pvs map is indexed by pv's name.
func PVSByStorageClass(ctx context.Context, cli kubernetes.Interface, scname string) (map[string]corev1.PersistentVolume, error) {
	allpvs, err := cli.CoreV1().PersistentVolumes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get persistent volumes: %w", err)
	}

	pvs := map[string]corev1.PersistentVolume{}
	for _, pv := range allpvs.Items {
		if pv.Spec.StorageClassName != scname {
			continue
		}
		pvs[pv.Name] = *pv.DeepCopy()
	}
	return pvs, nil
}

// PVCSForPVs returns a pv to pvc mapping. the returned map is indexed by the pv name.
func PVCSForPVs(ctx context.Context, cli kubernetes.Interface, pvs map[string]corev1.PersistentVolume) (map[string]corev1.PersistentVolumeClaim, error) {
	pvcs := map[string]corev1.PersistentVolumeClaim{}
	for pvidx, pv := range pvs {
		cref := pv.Spec.ClaimRef
		if cref == nil {
			return nil, fmt.Errorf("pv %s without associated PVC", pvidx)
		}

		pvc, err := cli.CoreV1().PersistentVolumeClaims(cref.Namespace).Get(ctx, cref.Name, metav1.GetOptions{})
		if err != nil {
			return nil, fmt.Errorf("failed to get pvc %s for pv %s: %w", cref.Name, pvidx, err)
		}

		pvcs[pvidx] = *pvc.DeepCopy()
	}
	return pvcs, nil
}
