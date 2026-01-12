package rook

import (
	"context"
	"fmt"
	"sort"
	"testing"

	"github.com/replicatedhq/kurl/pkg/rook/testfiles"
	"github.com/stretchr/testify/require"
	"gotest.tools/assert"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer/json"
	"k8s.io/client-go/kubernetes/fake"
	"k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	fakeclient "sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func Test_scaleDownPodOwnerDeployment(t *testing.T) {
	tests := []struct {
		name      string
		resources []byte
		namespace string
		objName   string
		podName   string
	}{
		{
			name:      "scale down deployment",
			resources: testfiles.ScalePodOwnerDeploy,
			namespace: "testns",
			objName:   "task-pv-deploy",
			podName:   "task-pv-deploy-77946dc8bf-ck9s8",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resources := runtimeObjectsFromList(t, tt.resources)
			clientset := fake.NewClientset(resources...)

			obj, err := clientset.AppsV1().Deployments(tt.namespace).Get(context.Background(), tt.objName, metav1.GetOptions{})
			require.NoError(t, err)
			replicas := int32(1)
			if obj.Spec.Replicas != nil {
				replicas = *obj.Spec.Replicas
			}

			pod, err := clientset.CoreV1().Pods(tt.namespace).Get(context.Background(), tt.podName, metav1.GetOptions{})
			require.NoError(t, err)
			err = scaleDownPodOwner(context.Background(), clientset, pod)
			require.NoError(t, err)

			obj, err = clientset.AppsV1().Deployments(tt.namespace).Get(context.Background(), tt.objName, metav1.GetOptions{})
			require.NoError(t, err)
			assert.Equal(t, int32(0), *obj.Spec.Replicas)

			err = scaleBackDeployment(context.Background(), clientset, obj)
			require.NoError(t, err)

			obj, err = clientset.AppsV1().Deployments(tt.namespace).Get(context.Background(), tt.objName, metav1.GetOptions{})
			require.NoError(t, err)
			assert.Equal(t, replicas, *obj.Spec.Replicas)
		})
	}
}

func Test_scaleDownPodOwnerStatefulSet(t *testing.T) {
	tests := []struct {
		name      string
		resources []byte
		namespace string
		objName   string
		podNames  []string
	}{
		{
			name:      "scale down statefulset",
			resources: testfiles.ScalePodOwnerSts,
			namespace: "testns",
			objName:   "task-pv-sts",
			podNames:  []string{"task-pv-sts-0", "task-pv-sts-1", "task-pv-sts-2"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resources := runtimeObjectsFromList(t, tt.resources)
			clientset := fake.NewClientset(resources...)

			obj, err := clientset.AppsV1().StatefulSets(tt.namespace).Get(context.Background(), tt.objName, metav1.GetOptions{})
			require.NoError(t, err)
			replicas := int32(1)
			if obj.Spec.Replicas != nil {
				replicas = *obj.Spec.Replicas
			}

			pods := []*corev1.Pod{}
			for _, podName := range tt.podNames {
				pod, err := clientset.CoreV1().Pods(tt.namespace).Get(context.Background(), podName, metav1.GetOptions{})
				require.NoError(t, err)
				pods = append(pods, pod)
			}
			for _, pod := range pods {
				err = scaleDownPodOwner(context.Background(), clientset, pod)
				require.NoError(t, err)
			}

			obj, err = clientset.AppsV1().StatefulSets(tt.namespace).Get(context.Background(), tt.objName, metav1.GetOptions{})
			require.NoError(t, err)
			assert.Equal(t, int32(0), *obj.Spec.Replicas)

			fmt.Println(obj.Annotations)
			err = scaleBackStatefulSet(context.Background(), clientset, obj)
			require.NoError(t, err)

			obj, err = clientset.AppsV1().StatefulSets(tt.namespace).Get(context.Background(), tt.objName, metav1.GetOptions{})
			require.NoError(t, err)
			assert.Equal(t, replicas, *obj.Spec.Replicas)
		})
	}
}

func Test_listPVCsByStorageClass(t *testing.T) {
	tests := []struct {
		name      string
		resources []byte
		scName    string
		wantPVCs  []string
	}{
		{
			name:      "list pvc by storage class",
			resources: testfiles.ListPVCsByStorageClass,
			scName:    "default",
			wantPVCs: []string{
				"testns.task-pv-claim",
				"testns.task-pv-storage-task-pv-sts-0",
				"testns.task-pv-storage-task-pv-sts-1",
				"testns.task-pv-storage-task-pv-sts-2",
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resources := runtimeObjectsFromList(t, tt.resources)
			clientset := fake.NewClientset(resources...)

			got, err := listPVCsByStorageClass(context.Background(), clientset, tt.scName)
			require.NoError(t, err)
			gotPVCs := []string{}
			for _, pvc := range got {
				gotPVCs = append(gotPVCs, pvc.Namespace+"."+pvc.Name)
			}
			sort.Strings(tt.wantPVCs)
			sort.Strings(gotPVCs)
			assert.DeepEqual(t, tt.wantPVCs, gotPVCs)
		})
	}
}

func Test_runFlexMigrator(t *testing.T) {
	tests := []struct {
		name string
		opts FlexvolumeToCSIOpts
	}{
		{
			name: "migrate flexvolume to csi",
			opts: FlexvolumeToCSIOpts{
				NodeName:          "node1",
				PVMigratorBinPath: "/path/to/pv-migrator",
				CephMigratorImage: "ceph/migrator:latest",
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cli := fakeclient.NewClientBuilder().Build()

			err := runFlexMigrator(context.Background(), cli, tt.opts)
			require.NoError(t, err)

			obj := &appsv1.Deployment{}
			err = cli.Get(context.Background(), client.ObjectKey{Namespace: "rook-ceph", Name: "rook-ceph-migrator"}, obj)
			require.NoError(t, err)

			assert.Equal(t, tt.opts.NodeName, obj.Spec.Template.Spec.NodeName)
			assert.Equal(t, tt.opts.PVMigratorBinPath, obj.Spec.Template.Spec.Volumes[0].HostPath.Path)
			assert.Equal(t, tt.opts.CephMigratorImage, obj.Spec.Template.Spec.Containers[0].Image)
			assert.Equal(t, "/usr/local/bin/pv-migrator", obj.Spec.Template.Spec.Containers[0].VolumeMounts[0].MountPath)
		})
	}
}

func runtimeObjectsFromList(t *testing.T, raw []byte) (objs []runtime.Object) {
	var list corev1.List
	s := json.NewSerializer(json.DefaultMetaFactory, scheme.Scheme, scheme.Scheme, false)
	_, _, err := s.Decode(raw, nil, &list)
	if err != nil {
		t.Fatalf("failed to decode kubernetes resource list: %v", err)
	}
	for _, item := range list.Items {
		item.Object, _, err = s.Decode(item.Raw, nil, nil)
		if err != nil {
			t.Fatalf("failed to decode kubernetes resource: %v", err)
		}
		objs = append(objs, item.Object)
	}
	return objs
}
