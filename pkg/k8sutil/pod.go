package k8sutil

import (
	corev1 "k8s.io/api/core/v1"
)

// HasPVC returs true if provided pod has provided pvc among its volumes.
func HasPVC(pod corev1.Pod, pvc corev1.PersistentVolumeClaim) bool {
	if pod.Namespace != pvc.Namespace {
		return false
	}

	for _, vol := range pod.Spec.Volumes {
		if vol.PersistentVolumeClaim == nil {
			continue
		}
		if vol.PersistentVolumeClaim.ClaimName != pvc.Name {
			continue
		}
		return true
	}

	return false
}
