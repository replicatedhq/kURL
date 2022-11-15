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
	if _, err := cli.StorageV1().StorageClasses().Get(ctx, scname, metav1.GetOptions{}); err != nil {
		return nil, fmt.Errorf("failed to get storage class %s: %w", scname, err)
	}

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

// PVSReservationPerNode return the sum of space of all pvs being served per node. this function
// also returns sum of space in pvs that exist bur are not in attached to any pod.
func PVSReservationPerNode(ctx context.Context, cli kubernetes.Interface, scname string) (map[string]int64, int64, error) {
	pvs, err := PVSByStorageClass(ctx, cli, scname)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to get pvs: %w", err)
	}

	pvcs, err := PVCSForPVs(ctx, cli, pvs)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to get pvcs for pvs: %w", err)
	}

	var detached int64
	attached := map[string]int64{}
	cache := map[string][]corev1.Pod{}
	for pvidx, pvc := range pvcs {
		pv, ok := pvs[pvidx]
		if !ok {
			pvcidx := fmt.Sprintf("%s/%s", pvc.Namespace, pvc.Name)
			return nil, 0, fmt.Errorf("pv %s for pvc %s not found", pvidx, pvcidx)
		}

		pods, ok := cache[pvc.Namespace]
		if !ok {
			list, err := cli.CoreV1().Pods(pvc.Namespace).List(ctx, metav1.ListOptions{})
			if err != nil {
				return nil, 0, fmt.Errorf("failed to list pods in namespace %s: %w", pvc.Namespace, err)
			}
			cache[pvc.Namespace] = list.Items
			pods = cache[pvc.Namespace]
		}

		var inuse bool
		for _, pod := range pods {
			if !HasPVC(pod, pvc) {
				continue
			}

			bytes, dec := pv.Spec.Capacity.Storage().AsInt64()
			if !dec {
				return nil, 0, fmt.Errorf("failed to parse pv %s storage size: %w", pvidx, err)
			}
			inuse = true
			attached[pod.Spec.NodeName] += bytes
			break
		}

		if inuse {
			continue
		}

		bytes, dec := pv.Spec.Capacity.Storage().AsInt64()
		if !dec {
			return nil, 0, fmt.Errorf("failed to parse pv %s storage size: %w", pvidx, err)
		}
		detached += bytes
	}

	return attached, detached, nil
}
