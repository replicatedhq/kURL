package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/vmware-tanzu/velero/pkg/plugin/velero"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
)

func TestRestoreKotsadmPluginExecute(t *testing.T) {
	tests := []struct {
		name        string
		configMaps  []runtime.Object
		deployment  *appsv1.Deployment
		statefulset *appsv1.StatefulSet
		replicaset  *appsv1.ReplicaSet
		pod         *corev1.Pod
		want        corev1.PodSpec
		wantErr     bool
	}{
		{
			name: "deployment",
			configMaps: []runtime.Object{
				&corev1.ConfigMap{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "kotsadm-restore-config",
						Namespace: "velero",
						Labels: map[string]string{
							"velero.io/plugin-config":        "",
							"kurl.sh/restore-kotsadm-plugin": "RestoreItemAction",
						},
					},
					Data: map[string]string{
						"HTTP_PROXY":  "http://10.128.0.3:3128",
						"HTTPS_PROXY": "https://10.128.0.3:3128",
						"NO_PROXY":    ".minio,10.128.0.50",
						"hostCAPath":  "/etc/pki/tls/ca-bundle.pem",
					},
				},
			},
			deployment: &appsv1.Deployment{
				TypeMeta: metav1.TypeMeta{
					APIVersion: "apps/v1",
					Kind:       "Deployment",
				},
				ObjectMeta: metav1.ObjectMeta{
					Name: "kotsadm",
				},
				Spec: appsv1.DeploymentSpec{
					Template: corev1.PodTemplateSpec{
						Spec: corev1.PodSpec{
							Containers: []corev1.Container{
								{
									Name: "kotsadm",
									Env: []corev1.EnvVar{
										{
											Name:  "HTTP_PROXY",
											Value: "http://proxy.internal",
										},
										{
											Name:  "HTTPS_PROXY",
											Value: "https://proxy.internal",
										},
										{
											Name:  "NO_PROXY",
											Value: ".rook-ceph,10.128.0.49",
										},
									},
								},
							},
							Volumes: []corev1.Volume{
								{
									Name: "host-cacerts",
									VolumeSource: corev1.VolumeSource{
										HostPath: &corev1.HostPathVolumeSource{
											Path: "/etc/ssl/cacerts.pem",
										},
									},
								},
							},
						},
					},
				},
			},
			want: corev1.PodSpec{
				Containers: []corev1.Container{
					{
						Name: "kotsadm",
						Env: []corev1.EnvVar{
							{
								Name:  "HTTP_PROXY",
								Value: "http://10.128.0.3:3128",
							},
							{
								Name:  "HTTPS_PROXY",
								Value: "https://10.128.0.3:3128",
							},
							{
								Name:  "NO_PROXY",
								Value: ".minio,10.128.0.50",
							},
						},
					},
				},
				Volumes: []corev1.Volume{
					{
						Name: "host-cacerts",
						VolumeSource: corev1.VolumeSource{
							HostPath: &corev1.HostPathVolumeSource{
								Path: "/etc/pki/tls/ca-bundle.pem",
							},
						},
					},
				},
			},
		},
		{
			name: "statefulset",
			configMaps: []runtime.Object{
				&corev1.ConfigMap{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "kotsadm-restore-config",
						Namespace: "velero",
						Labels: map[string]string{
							"velero.io/plugin-config":        "",
							"kurl.sh/restore-kotsadm-plugin": "RestoreItemAction",
						},
					},
					Data: map[string]string{
						"HTTP_PROXY":  "http://10.128.0.3:3128",
						"HTTPS_PROXY": "https://10.128.0.3:3128",
						"NO_PROXY":    ".minio,10.128.0.50",
						"hostCAPath":  "/etc/pki/tls/ca-bundle.pem",
					},
				},
			},
			statefulset: &appsv1.StatefulSet{
				TypeMeta: metav1.TypeMeta{
					APIVersion: "apps/v1",
					Kind:       "StatefulSet",
				},
				ObjectMeta: metav1.ObjectMeta{
					Name: "kotsadm",
				},
				Spec: appsv1.StatefulSetSpec{
					Template: corev1.PodTemplateSpec{
						Spec: corev1.PodSpec{
							Containers: []corev1.Container{
								{
									Name: "kotsadm",
									Env: []corev1.EnvVar{
										{
											Name:  "HTTP_PROXY",
											Value: "http://proxy.internal",
										},
										{
											Name:  "HTTPS_PROXY",
											Value: "https://proxy.internal",
										},
										{
											Name:  "NO_PROXY",
											Value: ".rook-ceph,10.128.0.49",
										},
									},
								},
							},
							Volumes: []corev1.Volume{
								{
									Name: "host-cacerts",
									VolumeSource: corev1.VolumeSource{
										HostPath: &corev1.HostPathVolumeSource{
											Path: "/etc/ssl/cacerts.pem",
										},
									},
								},
							},
						},
					},
				},
			},
			want: corev1.PodSpec{
				Containers: []corev1.Container{
					{
						Name: "kotsadm",
						Env: []corev1.EnvVar{
							{
								Name:  "HTTP_PROXY",
								Value: "http://10.128.0.3:3128",
							},
							{
								Name:  "HTTPS_PROXY",
								Value: "https://10.128.0.3:3128",
							},
							{
								Name:  "NO_PROXY",
								Value: ".minio,10.128.0.50",
							},
						},
					},
				},
				Volumes: []corev1.Volume{
					{
						Name: "host-cacerts",
						VolumeSource: corev1.VolumeSource{
							HostPath: &corev1.HostPathVolumeSource{
								Path: "/etc/pki/tls/ca-bundle.pem",
							},
						},
					},
				},
			},
		},
		{
			name: "replicaset",
			configMaps: []runtime.Object{
				&corev1.ConfigMap{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "kotsadm-restore-config",
						Namespace: "velero",
						Labels: map[string]string{
							"velero.io/plugin-config":        "",
							"kurl.sh/restore-kotsadm-plugin": "RestoreItemAction",
						},
					},
					Data: map[string]string{
						"HTTP_PROXY":  "http://10.128.0.3:3128",
						"HTTPS_PROXY": "https://10.128.0.3:3128",
						"NO_PROXY":    ".minio,10.128.0.50",
						"hostCAPath":  "/etc/pki/tls/ca-bundle.pem",
					},
				},
			},
			replicaset: &appsv1.ReplicaSet{
				TypeMeta: metav1.TypeMeta{
					APIVersion: "apps/v1",
					Kind:       "ReplicaSet",
				},
				ObjectMeta: metav1.ObjectMeta{
					Name: "kotsadm-577fd8c96f",
					Labels: map[string]string{
						"app": "kotsadm",
					},
				},
				Spec: appsv1.ReplicaSetSpec{
					Template: corev1.PodTemplateSpec{
						Spec: corev1.PodSpec{
							Containers: []corev1.Container{
								{
									Name: "kotsadm",
									Env: []corev1.EnvVar{
										{
											Name:  "HTTP_PROXY",
											Value: "http://proxy.internal",
										},
										{
											Name:  "HTTPS_PROXY",
											Value: "https://proxy.internal",
										},
										{
											Name:  "NO_PROXY",
											Value: ".rook-ceph,10.128.0.49",
										},
									},
								},
							},
							Volumes: []corev1.Volume{
								{
									Name: "host-cacerts",
									VolumeSource: corev1.VolumeSource{
										HostPath: &corev1.HostPathVolumeSource{
											Path: "/etc/ssl/cacerts.pem",
										},
									},
								},
							},
						},
					},
				},
			},
			want: corev1.PodSpec{
				Containers: []corev1.Container{
					{
						Name: "kotsadm",
						Env: []corev1.EnvVar{
							{
								Name:  "HTTP_PROXY",
								Value: "http://10.128.0.3:3128",
							},
							{
								Name:  "HTTPS_PROXY",
								Value: "https://10.128.0.3:3128",
							},
							{
								Name:  "NO_PROXY",
								Value: ".minio,10.128.0.50",
							},
						},
					},
				},
				Volumes: []corev1.Volume{
					{
						Name: "host-cacerts",
						VolumeSource: corev1.VolumeSource{
							HostPath: &corev1.HostPathVolumeSource{
								Path: "/etc/pki/tls/ca-bundle.pem",
							},
						},
					},
				},
			},
		},
		{
			name: "pod",
			configMaps: []runtime.Object{
				&corev1.ConfigMap{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "kotsadm-restore-config",
						Namespace: "velero",
						Labels: map[string]string{
							"velero.io/plugin-config":        "",
							"kurl.sh/restore-kotsadm-plugin": "RestoreItemAction",
						},
					},
					Data: map[string]string{
						"HTTP_PROXY":  "http://10.128.0.3:3128",
						"HTTPS_PROXY": "https://10.128.0.3:3128",
						"NO_PROXY":    ".minio,10.128.0.50",
						"hostCAPath":  "/etc/pki/tls/ca-bundle.pem",
					},
				},
			},
			pod: &corev1.Pod{
				TypeMeta: metav1.TypeMeta{
					APIVersion: "v1",
					Kind:       "Pod",
				},
				ObjectMeta: metav1.ObjectMeta{
					Name: "kotsadm-5797656748-6vhht",
					Labels: map[string]string{
						"app": "kotsadm",
					},
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name: "kotsadm",
							Env: []corev1.EnvVar{
								{
									Name:  "HTTP_PROXY",
									Value: "http://proxy.internal",
								},
								{
									Name:  "HTTPS_PROXY",
									Value: "https://proxy.internal",
								},
								{
									Name:  "NO_PROXY",
									Value: ".rook-ceph,10.128.0.49",
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							Name: "host-cacerts",
							VolumeSource: corev1.VolumeSource{
								HostPath: &corev1.HostPathVolumeSource{
									Path: "/etc/ssl/cacerts.pem",
								},
							},
						},
					},
				},
			},
			want: corev1.PodSpec{
				Containers: []corev1.Container{
					{
						Name: "kotsadm",
						Env: []corev1.EnvVar{
							{
								Name:  "HTTP_PROXY",
								Value: "http://10.128.0.3:3128",
							},
							{
								Name:  "HTTPS_PROXY",
								Value: "https://10.128.0.3:3128",
							},
							{
								Name:  "NO_PROXY",
								Value: ".minio,10.128.0.50",
							},
						},
					},
				},
				Volumes: []corev1.Volume{
					{
						Name: "host-cacerts",
						VolumeSource: corev1.VolumeSource{
							HostPath: &corev1.HostPathVolumeSource{
								Path: "/etc/pki/tls/ca-bundle.pem",
							},
						},
					},
				},
			},
		},
	}

	t.Setenv("VELERO_NAMESPACE", "velero")

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			clientset := fake.NewClientset(test.configMaps...)
			p := &restoreKotsadmPlugin{
				client: clientset,
			}

			var obj map[string]interface{}
			var err error
			if test.deployment != nil {
				obj, err = runtime.DefaultUnstructuredConverter.ToUnstructured(test.deployment)
			} else if test.statefulset != nil {
				obj, err = runtime.DefaultUnstructuredConverter.ToUnstructured(test.statefulset)
			} else if test.replicaset != nil {
				obj, err = runtime.DefaultUnstructuredConverter.ToUnstructured(test.replicaset)
			} else if test.pod != nil {
				obj, err = runtime.DefaultUnstructuredConverter.ToUnstructured(test.pod)
			}
			require.NoError(t, err)

			input := &velero.RestoreItemActionExecuteInput{
				Item: &unstructured.Unstructured{
					Object: obj,
				},
			}

			output, err := p.Execute(input)

			if test.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}

			var spec corev1.PodSpec

			if test.deployment != nil {
				updatedDeployment := &appsv1.Deployment{}
				err := runtime.DefaultUnstructuredConverter.FromUnstructured(output.UpdatedItem.UnstructuredContent(), updatedDeployment)
				require.NoError(t, err)
				spec = updatedDeployment.Spec.Template.Spec
			} else if test.statefulset != nil {
				updatedStatefulSet := &appsv1.StatefulSet{}
				err := runtime.DefaultUnstructuredConverter.FromUnstructured(output.UpdatedItem.UnstructuredContent(), updatedStatefulSet)
				require.NoError(t, err)
				spec = updatedStatefulSet.Spec.Template.Spec
			} else if test.replicaset != nil {
				updatedReplicaSet := &appsv1.ReplicaSet{}
				err := runtime.DefaultUnstructuredConverter.FromUnstructured(output.UpdatedItem.UnstructuredContent(), updatedReplicaSet)
				require.NoError(t, err)
				spec = updatedReplicaSet.Spec.Template.Spec
			} else if test.pod != nil {
				updatedPod := &corev1.Pod{}
				err := runtime.DefaultUnstructuredConverter.FromUnstructured(output.UpdatedItem.UnstructuredContent(), updatedPod)
				require.NoError(t, err)
				spec = updatedPod.Spec
			}

			assert.Equal(t, test.want, spec)
		})
	}
}
