package k8sutil

import (
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestPodUsesPVC(t *testing.T) {
	for _, tt := range []struct {
		name     string
		expected bool
		pod      corev1.Pod
		pvc      corev1.PersistentVolumeClaim
	}{
		{
			name:     "uses pvc",
			expected: true,
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "pod",
					Namespace: "teste",
				},
				Spec: corev1.PodSpec{
					Volumes: []corev1.Volume{
						{
							Name: "vol",
							VolumeSource: corev1.VolumeSource{
								PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
									ClaimName: "pvc",
								},
							},
						},
					},
				},
			},
			pvc: corev1.PersistentVolumeClaim{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "pvc",
					Namespace: "teste",
				},
			},
		},
		{
			name:     "nil claimref",
			expected: false,
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "pod",
					Namespace: "teste",
				},
				Spec: corev1.PodSpec{
					Volumes: []corev1.Volume{
						{
							Name: "vol",
						},
					},
				},
			},
			pvc: corev1.PersistentVolumeClaim{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "pvc",
					Namespace: "teste",
				},
			},
		},
		{
			name:     "different namespace",
			expected: false,
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "pod",
					Namespace: "teste",
				},
				Spec: corev1.PodSpec{
					Volumes: []corev1.Volume{
						{
							Name: "vol",
							VolumeSource: corev1.VolumeSource{
								PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
									ClaimName: "pvc",
								},
							},
						},
					},
				},
			},
			pvc: corev1.PersistentVolumeClaim{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "pvc",
					Namespace: "another-namespace",
				},
			},
		},
		{
			name:     "does not use pvc",
			expected: false,
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "pod",
					Namespace: "teste",
				},
				Spec: corev1.PodSpec{
					Volumes: []corev1.Volume{
						{
							Name: "vol",
							VolumeSource: corev1.VolumeSource{
								PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
									ClaimName: "another-pvc",
								},
							},
						},
					},
				},
			},
			pvc: corev1.PersistentVolumeClaim{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "pvc",
					Namespace: "teste",
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			result := PodUsesPVC(tt.pod, tt.pvc)
			if result != tt.expected {
				t.Errorf("expected %v, received %v", tt.expected, result)
			}
		})
	}
}
