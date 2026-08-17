package cli

import (
	"context"
	"io"
	"log"
	"testing"

	"github.com/stretchr/testify/require"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	lhv1b2 "github.com/longhorn/longhorn-manager/k8s/pkg/apis/longhorn/v1beta2"
	"github.com/stretchr/testify/assert"
)

func Test_scaleDownReplicas(t *testing.T) {
	discardLogger := log.New(io.Discard, "", 0)

	scaleDownReplicasWaitTime = 0
	volumes := []client.Object{
		&lhv1b2.Volume{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "vol-0",
				Namespace: longhornNamespace,
			},
			Spec: lhv1b2.VolumeSpec{
				NumberOfReplicas: 3,
			},
		},
		&lhv1b2.Volume{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "vol-1",
				Namespace: longhornNamespace,
			},
			Spec: lhv1b2.VolumeSpec{
				NumberOfReplicas: 3,
			},
		},
		&lhv1b2.Volume{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "vol-2",
				Namespace: longhornNamespace,
			},
			Spec: lhv1b2.VolumeSpec{
				NumberOfReplicas: 3,
			},
		},
	}

	scheme := runtime.NewScheme()
	lhv1b2.AddToScheme(scheme)
	cli := fake.NewClientBuilder().WithScheme(scheme).WithObjects(volumes...).Build()
	scaled, err := scaleDownReplicas(context.Background(), discardLogger, cli)
	assert.True(t, scaled)
	require.NoError(t, err)

	var gotVolumes lhv1b2.VolumeList
	err = cli.List(context.Background(), &gotVolumes, &client.ListOptions{})
	require.NoError(t, err)

	for _, vol := range gotVolumes.Items {
		assert.Equal(t, int(1), vol.Spec.NumberOfReplicas)
		assert.Equal(t, "3", vol.Annotations[pvmigrateScaleDownAnnotation])
	}
}

func Test_unhealthyVolumes(t *testing.T) {
	discardLogger := log.New(io.Discard, "", 0)

	for _, tt := range []struct {
		name     string
		expected []string
		objects  []client.Object
	}{
		{
			name:    "if no volumes then returns as healthy",
			objects: []client.Object{},
		},
		{
			name: "if the volume is not attached then it is should be considered healthy",
			objects: []client.Object{
				&lhv1b2.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b2.VolumeStatus{
						State: lhv1b2.VolumeStateDetached,
					},
				},
			},
		},
		{
			name:     "if the volume is not scheduled then it is should be considered unhealthy",
			expected: []string{"volume-0"},
			objects: []client.Object{
				&lhv1b2.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b2.VolumeStatus{
						State: lhv1b2.VolumeStateAttached,
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.VolumeConditionTypeScheduled,
								Status: lhv1b2.ConditionStatusFalse,
							},
						},
					},
				},
			},
		},
		{
			name:     "if the volume robustness is not healthy then the volume is not healthy",
			expected: []string{"volume-0"},
			objects: []client.Object{
				&lhv1b2.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b2.VolumeStatus{
						State:      lhv1b2.VolumeStateAttached,
						Robustness: lhv1b2.VolumeRobustnessUnknown,
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.VolumeConditionTypeScheduled,
								Status: lhv1b2.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
		{
			name: "healthy volume should not be included in the result",
			objects: []client.Object{
				&lhv1b2.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b2.VolumeStatus{
						State:      lhv1b2.VolumeStateAttached,
						Robustness: lhv1b2.VolumeRobustnessHealthy,
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.VolumeConditionTypeScheduled,
								Status: lhv1b2.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
		{
			name: "detached unhealthy volumes should be ignored",
			objects: []client.Object{
				&lhv1b2.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b2.VolumeStatus{
						State:      lhv1b2.VolumeStateDetached,
						Robustness: lhv1b2.VolumeRobustnessDegraded,
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.VolumeConditionTypeScheduled,
								Status: lhv1b2.ConditionStatusTrue,
							},
						},
					},
				},
				&lhv1b2.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-1",
						Namespace: longhornNamespace,
					},
					Status: lhv1b2.VolumeStatus{
						State:      lhv1b2.VolumeStateAttached,
						Robustness: lhv1b2.VolumeRobustnessHealthy,
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.VolumeConditionTypeScheduled,
								Status: lhv1b2.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			scheme := runtime.NewScheme()
			lhv1b2.AddToScheme(scheme)
			cli := fake.NewClientBuilder().WithScheme(scheme).WithObjects(tt.objects...).Build()
			result, err := unhealthyVolumes(context.Background(), discardLogger, cli)
			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_unhealthyNodes(t *testing.T) {
	discardLogger := log.New(io.Discard, "", 0)

	for _, tt := range []struct {
		name     string
		expected []string
		objects  []client.Object
	}{
		{
			name:    "if no nodes then returns as healthy",
			objects: []client.Object{},
		},
		{
			name:     "if the node is not ready then it is should be considered unhealthy",
			expected: []string{"node-0"},
			objects: []client.Object{
				&lhv1b2.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b2.NodeStatus{
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.NodeConditionTypeReady,
								Status: lhv1b2.ConditionStatusFalse,
							},
						},
					},
				},
			},
		},
		{
			name:     "if the node is not schedulable then it is should be considered unhealthy",
			expected: []string{"node-0"},
			objects: []client.Object{
				&lhv1b2.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b2.NodeStatus{
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.NodeConditionTypeReady,
								Status: lhv1b2.ConditionStatusTrue,
							},
							{
								Type:   lhv1b2.NodeConditionTypeSchedulable,
								Status: lhv1b2.ConditionStatusFalse,
							},
						},
					},
				},
			},
		},
		{
			name:     "if the node contain a disk that is not ready then it is should be considered unhealthy",
			expected: []string{"node-0"},
			objects: []client.Object{
				&lhv1b2.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b2.NodeStatus{
						DiskStatus: map[string]*lhv1b2.DiskStatus{
							"disk-0": {
								Conditions: []lhv1b2.Condition{
									{
										Type:   lhv1b2.DiskConditionTypeReady,
										Status: lhv1b2.ConditionStatusFalse,
									},
								},
							},
						},
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.NodeConditionTypeReady,
								Status: lhv1b2.ConditionStatusTrue,
							},
							{
								Type:   lhv1b2.NodeConditionTypeSchedulable,
								Status: lhv1b2.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
		{
			name:     "if the node contain a disk that is not scheduleable then it is should be considered unhealthy",
			expected: []string{"node-0"},
			objects: []client.Object{
				&lhv1b2.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b2.NodeStatus{
						DiskStatus: map[string]*lhv1b2.DiskStatus{
							"disk-0": {
								Conditions: []lhv1b2.Condition{
									{
										Type:   lhv1b2.DiskConditionTypeReady,
										Status: lhv1b2.ConditionStatusTrue,
									},
									{
										Type:   lhv1b2.DiskConditionTypeSchedulable,
										Status: lhv1b2.ConditionStatusFalse,
									},
								},
							},
						},
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.NodeConditionTypeReady,
								Status: lhv1b2.ConditionStatusTrue,
							},
							{
								Type:   lhv1b2.NodeConditionTypeSchedulable,
								Status: lhv1b2.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
		{
			name:     "if the node has not enough space in a disk then it is should be considered unhealthy",
			expected: []string{"node-0"},
			objects: []client.Object{
				&lhv1b2.Setting{
					ObjectMeta: metav1.ObjectMeta{
						Name:      overProvisioningSetting,
						Namespace: longhornNamespace,
					},
					Value: "100",
				},
				&lhv1b2.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b2.NodeStatus{
						DiskStatus: map[string]*lhv1b2.DiskStatus{
							"disk-0": {
								StorageScheduled: 100,
								StorageAvailable: 100,
								Conditions: []lhv1b2.Condition{
									{
										Type:   lhv1b2.DiskConditionTypeReady,
										Status: lhv1b2.ConditionStatusTrue,
									},
									{
										Type:   lhv1b2.DiskConditionTypeSchedulable,
										Status: lhv1b2.ConditionStatusTrue,
									},
								},
							},
						},
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.NodeConditionTypeReady,
								Status: lhv1b2.ConditionStatusTrue,
							},
							{
								Type:   lhv1b2.NodeConditionTypeSchedulable,
								Status: lhv1b2.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
		{
			name: "if disk usage is still under the threshold then it is should be considered healthy",
			objects: []client.Object{
				&lhv1b2.Setting{
					ObjectMeta: metav1.ObjectMeta{
						Name:      overProvisioningSetting,
						Namespace: longhornNamespace,
					},
					Value: "200",
				},
				&lhv1b2.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b2.NodeStatus{
						DiskStatus: map[string]*lhv1b2.DiskStatus{
							"disk-0": {
								StorageScheduled: 199,
								StorageAvailable: 100,
								Conditions: []lhv1b2.Condition{
									{
										Type:   lhv1b2.DiskConditionTypeReady,
										Status: lhv1b2.ConditionStatusTrue,
									},
									{
										Type:   lhv1b2.DiskConditionTypeSchedulable,
										Status: lhv1b2.ConditionStatusTrue,
									},
								},
							},
						},
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.NodeConditionTypeReady,
								Status: lhv1b2.ConditionStatusTrue,
							},
							{
								Type:   lhv1b2.NodeConditionTypeSchedulable,
								Status: lhv1b2.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
		{
			name:     "if only one of disk usage is over limit then the node is unhealthy",
			expected: []string{"node-0"},
			objects: []client.Object{
				&lhv1b2.Setting{
					ObjectMeta: metav1.ObjectMeta{
						Name:      overProvisioningSetting,
						Namespace: longhornNamespace,
					},
					Value: "200",
				},
				&lhv1b2.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b2.NodeStatus{
						DiskStatus: map[string]*lhv1b2.DiskStatus{
							"disk-0": {
								StorageScheduled: 199,
								StorageAvailable: 100,
								Conditions: []lhv1b2.Condition{
									{
										Type:   lhv1b2.DiskConditionTypeReady,
										Status: lhv1b2.ConditionStatusTrue,
									},
									{
										Type:   lhv1b2.DiskConditionTypeSchedulable,
										Status: lhv1b2.ConditionStatusTrue,
									},
								},
							},
							"disk-1": {
								StorageScheduled: 101,
								StorageAvailable: 50,
								Conditions: []lhv1b2.Condition{
									{
										Type:   lhv1b2.DiskConditionTypeReady,
										Status: lhv1b2.ConditionStatusTrue,
									},
									{
										Type:   lhv1b2.DiskConditionTypeSchedulable,
										Status: lhv1b2.ConditionStatusTrue,
									},
								},
							},
						},
						Conditions: []lhv1b2.Condition{
							{
								Type:   lhv1b2.NodeConditionTypeReady,
								Status: lhv1b2.ConditionStatusTrue,
							},
							{
								Type:   lhv1b2.NodeConditionTypeSchedulable,
								Status: lhv1b2.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			scheme := runtime.NewScheme()
			lhv1b2.AddToScheme(scheme)
			cli := fake.NewClientBuilder().WithScheme(scheme).WithObjects(tt.objects...).Build()
			result, err := unhealthyNodes(context.Background(), discardLogger, cli)
			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_nodeIs(t *testing.T) {
	for _, tt := range []struct {
		name      string
		expected  bool
		condition string
		node      lhv1b2.Node
	}{
		{
			name:      "if condition is not found then returns false",
			expected:  false,
			condition: "DiskConditionReasonDiskNotReady",
			node: lhv1b2.Node{
				Status: lhv1b2.NodeStatus{
					Conditions: []lhv1b2.Condition{
						{
							Type:   "foo",
							Status: "bar",
						},
					},
				},
			},
		},
		{
			name:      "if multiple conditions are present it should filter by the right one",
			expected:  true,
			condition: lhv1b2.NodeConditionTypeReady,
			node: lhv1b2.Node{
				Status: lhv1b2.NodeStatus{
					Conditions: []lhv1b2.Condition{
						{
							Type:   "foo",
							Status: lhv1b2.ConditionStatusFalse,
						},
						{
							Type:   "bar",
							Status: lhv1b2.ConditionStatusFalse,
						},
						{
							Type:   lhv1b2.NodeConditionTypeReady,
							Status: lhv1b2.ConditionStatusTrue,
						},
						{
							Type:   "baz",
							Status: lhv1b2.ConditionStatusFalse,
						},
					},
				},
			},
		},
		{
			name:      "condition is found and status is true then returns true",
			expected:  true,
			condition: lhv1b2.NodeConditionTypeReady,
			node: lhv1b2.Node{
				Status: lhv1b2.NodeStatus{
					Conditions: []lhv1b2.Condition{
						{
							Type:   lhv1b2.NodeConditionTypeReady,
							Status: lhv1b2.ConditionStatusTrue,
						},
					},
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got := nodeIs(tt.condition, tt.node)
			assert.Equal(t, tt.expected, got)
		})
	}
}
