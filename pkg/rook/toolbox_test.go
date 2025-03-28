package rook

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/replicatedhq/kurl/pkg/rook/testfiles"
	"github.com/stretchr/testify/require"
	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/fake"
	corev1client "k8s.io/client-go/kubernetes/typed/core/v1"
	restclient "k8s.io/client-go/rest"
)

type testWriter struct {
	t *testing.T
}

func (tw testWriter) Write(p []byte) (n int, err error) {
	tw.t.Log(string(p))
	return len(p), nil
}

type execResponses map[string]struct {
	errcode        int
	stdout, stderr string
	err            error
}

// test function only
func setToolboxExecFunc(responses execResponses) {
	execFunction = func(_ corev1client.CoreV1Interface, _ *restclient.Config, ns, pod, container string, command ...string) (int, string, string, error) {
		cmdIdx := strings.Join(append(command, ns, pod, container), " - ")
		res, ok := responses[cmdIdx]
		if ok {
			return res.errcode, res.stdout, res.stderr, res.err
		}
		return -1, "", "", fmt.Errorf("unrecognized command %q", cmdIdx)
	}
}

// test function only, contains panics
func runtimeFromDeploymentlistJSON(deploymentListJSON []byte) []runtime.Object {
	deploymentList := appsv1.DeploymentList{}
	err := json.Unmarshal(deploymentListJSON, &deploymentList)
	if err != nil {
		panic(err) // this is only called for unit tests, not at runtime
	}

	runtimeObjects := []runtime.Object{}
	for idx := range deploymentList.Items {
		runtimeObjects = append(runtimeObjects, &deploymentList.Items[idx])
	}
	return runtimeObjects
}

func Test_runToolboxCommand(t *testing.T) {
	tests := []struct {
		name      string
		command   []string
		resources []runtime.Object
		responses execResponses
		want      string
		wanterr   string
	}{
		{
			name:      "no toolbox pod running",
			command:   []string{"echo", "'hello world'"},
			resources: runtimeFromPodlistJSON(testfiles.HostpathPods),
			responses: map[string]struct {
				errcode        int
				stdout, stderr string
				err            error
			}{},
			wanterr: "found 0 rook-ceph-tools pods, with names \"\", expected 1",
		},
		{
			name:      "example exec",
			command:   []string{"echo", "'hello world'"},
			resources: runtimeFromPodlistJSON(testfiles.SixBlockDevicePods),
			responses: map[string]struct {
				errcode        int
				stdout, stderr string
				err            error
			}{
				`echo - 'hello world' - rook-ceph - rook-ceph-tools-785466cbdd-wk8rx - rook-ceph-tools`: {
					stdout: "arbitrary output",
				},
			},
			want: "arbitrary output",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)
			clientset := fake.NewSimpleClientset(tt.resources...)

			setToolboxExecFunc(tt.responses)
			conf = &restclient.Config{} // set the rest client so that runToolboxCommand does not attempt to fetch it

			got, _, err := runToolboxCommand(context.TODO(), clientset, tt.command)
			if tt.wanterr != "" {
				req.Error(err)
				req.EqualError(err, tt.wanterr)
			} else {
				req.NoError(err)
				req.Equal(tt.want, got)
			}
		})
	}
}

func Test_startToolbox(t *testing.T) {
	loopSleep = time.Millisecond * 20
	tests := []struct {
		name           string
		resources      []runtime.Object
		wantErr        string
		backgroundFunc func(context.Context, kubernetes.Interface)
		validatorFunc  func(context.Context, kubernetes.Interface) error
	}{
		{
			name:      "tools deployment exists and is already the correct scale",
			resources: runtimeFromDeploymentlistJSON(testfiles.Rook6OSDDeployments),
		},
		{
			name:      "no operator deployment exists",
			resources: nil,
			wantErr:   `unable to determine rook-ceph-operator image: unable to get rook-ceph-operator deployment: deployments.apps "rook-ceph-operator" not found`,
		},
		{
			name:      "tools deployment does not yet exist, but operator does",
			resources: runtimeFromDeploymentlistJSON(testfiles.RookHostpathDeployments),
			backgroundFunc: func(ctx context.Context, k kubernetes.Interface) {
				// watch for the statefulset to be scaled down, and then delete the pod
				for {
					select {
					case <-time.After(time.Second / 100):
						// check deployment, maybe set status
						toolbox, err := k.AppsV1().Deployments("rook-ceph").Get(ctx, "rook-ceph-tools", metav1.GetOptions{})
						if err != nil {
							continue
						}
						if toolbox.Spec.Replicas != nil {
							toolbox.Status.Replicas = *toolbox.Spec.Replicas
							toolbox.Status.ReadyReplicas = *toolbox.Spec.Replicas
							toolbox.Status.AvailableReplicas = *toolbox.Spec.Replicas
							toolbox.Status.UpdatedReplicas = *toolbox.Spec.Replicas

							_, err = k.AppsV1().Deployments("rook-ceph").UpdateStatus(ctx, toolbox, metav1.UpdateOptions{})
							if err != nil {
								panic(err)
							}
						}
					case <-ctx.Done():
						return
					}
				}
			},
			validatorFunc: func(ctx context.Context, k kubernetes.Interface) error {
				// ensure that a rook-ceph-tools deployment exists
				toolbox, err := k.AppsV1().Deployments("rook-ceph").Get(ctx, "rook-ceph-tools", metav1.GetOptions{})
				if err != nil {
					return fmt.Errorf("unable to find rook-ceph-tools deployment %w", err)
				}

				if toolbox.Spec.Replicas == nil || *toolbox.Spec.Replicas != 1 {
					return fmt.Errorf("rook-ceph-tools scale was %v not 1", toolbox.Spec.Replicas)
				}

				if toolbox.Spec.Template.Spec.Containers[0].Image != "kurlsh/rook-ceph:v1.0.4-9065b09-20210625" {
					return fmt.Errorf("rook-ceph-tools image was %s not 'kurlsh/rook-ceph:v1.0.4-9065b09-20210625'", toolbox.Spec.Template.Spec.Containers[0].Image)
				}
				return nil
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)
			clientset := fake.NewSimpleClientset(tt.resources...)
			InitWriter(testWriter{t: t})

			testCtx, cancelfunc := context.WithTimeout(context.Background(), time.Minute) // if your test takes more than 1m, there are issues
			defer cancelfunc()

			if tt.backgroundFunc != nil {
				go tt.backgroundFunc(testCtx, clientset)
			}

			err := startToolbox(testCtx, clientset)
			if tt.wantErr != "" {
				req.EqualError(err, tt.wantErr)
			} else {
				req.NoError(err)
			}

			if tt.validatorFunc != nil {
				err = tt.validatorFunc(testCtx, clientset)
				req.NoError(err)
			}
		})
	}
}
