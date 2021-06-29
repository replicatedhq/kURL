package main

import (
	"os"
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
	}

	os.Setenv("VELERO_NAMESPACE", "velero")

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			clientset := fake.NewSimpleClientset(test.configMaps...)
			p := &restoreKotsadmPlugin{
				client: clientset,
			}

			var obj map[string]interface{}
			var err error
			if test.deployment != nil {
				obj, err = runtime.DefaultUnstructuredConverter.ToUnstructured(test.deployment)
			} else {
				obj, err = runtime.DefaultUnstructuredConverter.ToUnstructured(test.statefulset)
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
			} else {
				updatedStatefulSet := &appsv1.StatefulSet{}
				err := runtime.DefaultUnstructuredConverter.FromUnstructured(output.UpdatedItem.UnstructuredContent(), updatedStatefulSet)
				require.NoError(t, err)
				spec = updatedStatefulSet.Spec.Template.Spec
			}

			assert.Equal(t, test.want, spec)
		})
	}
}
