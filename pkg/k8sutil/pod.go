package k8sutil

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// PodHasPVC returs true if provided pod has provided pvc among its volumes.
func PodHasPVC(pod corev1.Pod, pvcNamespace, pvcName string) bool {
	if pod.Namespace != pvcNamespace {
		return false
	}

	for _, vol := range pod.Spec.Volumes {
		if vol.PersistentVolumeClaim == nil {
			continue
		}
		if vol.PersistentVolumeClaim.ClaimName != pvcName {
			continue
		}
		return true
	}

	return false
}

// ListPodsBySelector returns a list of pods matching the provided selector.
func ListPodsBySelector(ctx context.Context, clientset kubernetes.Interface, namespace string, selector string) (*corev1.PodList, error) {
	return clientset.CoreV1().Pods(namespace).List(ctx, metav1.ListOptions{LabelSelector: selector})
}

// IsPodReady returns true if provided pod is ready.
func IsPodReady(pod corev1.Pod) bool {
	for _, cond := range pod.Status.Conditions {
		if cond.Type == corev1.PodReady && cond.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}
