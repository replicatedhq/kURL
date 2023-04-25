package cli

import (
	"context"
	"io"
	"log"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	lhv1b1 "github.com/longhorn/longhorn-manager/k8s/pkg/apis/longhorn/v1beta1"
	"github.com/stretchr/testify/assert"
)

func Test_scaleDownReplicas(t *testing.T) {
	discardLogger := log.New(io.Discard, "", 0)

	scaleDownReplicasWaitTime = 0
	volumes := []client.Object{
		&lhv1b1.Volume{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "vol-0",
				Namespace: longhornNamespace,
			},
			Spec: lhv1b1.VolumeSpec{
				NumberOfReplicas: 3,
			},
		},
		&lhv1b1.Volume{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "vol-1",
				Namespace: longhornNamespace,
			},
			Spec: lhv1b1.VolumeSpec{
				NumberOfReplicas: 3,
			},
		},
		&lhv1b1.Volume{
			ObjectMeta: metav1.ObjectMeta{
				Name:      "vol-2",
				Namespace: longhornNamespace,
			},
			Spec: lhv1b1.VolumeSpec{
				NumberOfReplicas: 3,
			},
		},
	}

	scheme := runtime.NewScheme()
	lhv1b1.AddToScheme(scheme)
	cli := fake.NewClientBuilder().WithScheme(scheme).WithObjects(volumes...).Build()
	scaled, err := scaleDownReplicas(context.Background(), discardLogger, cli)
	assert.True(t, scaled)
	assert.NoError(t, err)

	var gotVolumes lhv1b1.VolumeList
	err = cli.List(context.Background(), &gotVolumes, &client.ListOptions{})
	assert.NoError(t, err)

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
				&lhv1b1.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b1.VolumeStatus{
						State: lhv1b1.VolumeStateDetached,
					},
				},
			},
		},
		{
			name:     "if the volume is not scheduled then it is should be considered unhealthy",
			expected: []string{"volume-0"},
			objects: []client.Object{
				&lhv1b1.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b1.VolumeStatus{
						State: lhv1b1.VolumeStateAttached,
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.VolumeConditionTypeScheduled,
								Status: lhv1b1.ConditionStatusFalse,
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
				&lhv1b1.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b1.VolumeStatus{
						State:      lhv1b1.VolumeStateAttached,
						Robustness: lhv1b1.VolumeRobustnessUnknown,
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.VolumeConditionTypeScheduled,
								Status: lhv1b1.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
		{
			name: "healthy volume should not be included in the result",
			objects: []client.Object{
				&lhv1b1.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b1.VolumeStatus{
						State:      lhv1b1.VolumeStateAttached,
						Robustness: lhv1b1.VolumeRobustnessHealthy,
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.VolumeConditionTypeScheduled,
								Status: lhv1b1.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
		{
			name: "detached unhealthy volumes should be ignored",
			objects: []client.Object{
				&lhv1b1.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-0",
						Namespace: longhornNamespace,
					},
					Status: lhv1b1.VolumeStatus{
						State:      lhv1b1.VolumeStateDetached,
						Robustness: lhv1b1.VolumeRobustnessDegraded,
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.VolumeConditionTypeScheduled,
								Status: lhv1b1.ConditionStatusTrue,
							},
						},
					},
				},
				&lhv1b1.Volume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "volume-1",
						Namespace: longhornNamespace,
					},
					Status: lhv1b1.VolumeStatus{
						State:      lhv1b1.VolumeStateAttached,
						Robustness: lhv1b1.VolumeRobustnessHealthy,
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.VolumeConditionTypeScheduled,
								Status: lhv1b1.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			scheme := runtime.NewScheme()
			lhv1b1.AddToScheme(scheme)
			cli := fake.NewClientBuilder().WithScheme(scheme).WithObjects(tt.objects...).Build()
			result, err := unhealthyVolumes(context.Background(), discardLogger, cli)
			assert.NoError(t, err)
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
				&lhv1b1.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b1.NodeStatus{
						Conditions: map[string]lhv1b1.Condition{
							"": {
								Type:   lhv1b1.NodeConditionTypeReady,
								Status: lhv1b1.ConditionStatusFalse,
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
				&lhv1b1.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b1.NodeStatus{
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.NodeConditionTypeReady,
								Status: lhv1b1.ConditionStatusTrue,
							},
							"1": {
								Type:   lhv1b1.NodeConditionTypeSchedulable,
								Status: lhv1b1.ConditionStatusFalse,
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
				&lhv1b1.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b1.NodeStatus{
						DiskStatus: map[string]*lhv1b1.DiskStatus{
							"disk-0": {
								Conditions: map[string]lhv1b1.Condition{
									"0": {
										Type:   lhv1b1.DiskConditionTypeReady,
										Status: lhv1b1.ConditionStatusFalse,
									},
								},
							},
						},
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.NodeConditionTypeReady,
								Status: lhv1b1.ConditionStatusTrue,
							},
							"1": {
								Type:   lhv1b1.NodeConditionTypeSchedulable,
								Status: lhv1b1.ConditionStatusTrue,
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
				&lhv1b1.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b1.NodeStatus{
						DiskStatus: map[string]*lhv1b1.DiskStatus{
							"disk-0": {
								Conditions: map[string]lhv1b1.Condition{
									"0": {
										Type:   lhv1b1.DiskConditionTypeReady,
										Status: lhv1b1.ConditionStatusTrue,
									},
									"1": {
										Type:   lhv1b1.DiskConditionTypeSchedulable,
										Status: lhv1b1.ConditionStatusFalse,
									},
								},
							},
						},
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.NodeConditionTypeReady,
								Status: lhv1b1.ConditionStatusTrue,
							},
							"1": {
								Type:   lhv1b1.NodeConditionTypeSchedulable,
								Status: lhv1b1.ConditionStatusTrue,
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
				&lhv1b1.Setting{
					ObjectMeta: metav1.ObjectMeta{
						Name:      overProvisioningSetting,
						Namespace: longhornNamespace,
					},
					Value: "100",
				},
				&lhv1b1.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b1.NodeStatus{
						DiskStatus: map[string]*lhv1b1.DiskStatus{
							"disk-0": {
								StorageScheduled: 100,
								StorageAvailable: 100,
								Conditions: map[string]lhv1b1.Condition{
									"0": {
										Type:   lhv1b1.DiskConditionTypeReady,
										Status: lhv1b1.ConditionStatusTrue,
									},
									"1": {
										Type:   lhv1b1.DiskConditionTypeSchedulable,
										Status: lhv1b1.ConditionStatusTrue,
									},
								},
							},
						},
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.NodeConditionTypeReady,
								Status: lhv1b1.ConditionStatusTrue,
							},
							"1": {
								Type:   lhv1b1.NodeConditionTypeSchedulable,
								Status: lhv1b1.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
		{
			name: "if disk usage is still under the threshold then it is should be considered healthy",
			objects: []client.Object{
				&lhv1b1.Setting{
					ObjectMeta: metav1.ObjectMeta{
						Name:      overProvisioningSetting,
						Namespace: longhornNamespace,
					},
					Value: "200",
				},
				&lhv1b1.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b1.NodeStatus{
						DiskStatus: map[string]*lhv1b1.DiskStatus{
							"disk-0": {
								StorageScheduled: 199,
								StorageAvailable: 100,
								Conditions: map[string]lhv1b1.Condition{
									"0": {
										Type:   lhv1b1.DiskConditionTypeReady,
										Status: lhv1b1.ConditionStatusTrue,
									},
									"1": {
										Type:   lhv1b1.DiskConditionTypeSchedulable,
										Status: lhv1b1.ConditionStatusTrue,
									},
								},
							},
						},
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.NodeConditionTypeReady,
								Status: lhv1b1.ConditionStatusTrue,
							},
							"1": {
								Type:   lhv1b1.NodeConditionTypeSchedulable,
								Status: lhv1b1.ConditionStatusTrue,
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
				&lhv1b1.Setting{
					ObjectMeta: metav1.ObjectMeta{
						Name:      overProvisioningSetting,
						Namespace: longhornNamespace,
					},
					Value: "200",
				},
				&lhv1b1.Node{
					ObjectMeta: metav1.ObjectMeta{
						Name: "node-0",
					},
					Status: lhv1b1.NodeStatus{
						DiskStatus: map[string]*lhv1b1.DiskStatus{
							"disk-0": {
								StorageScheduled: 199,
								StorageAvailable: 100,
								Conditions: map[string]lhv1b1.Condition{
									"0": {
										Type:   lhv1b1.DiskConditionTypeReady,
										Status: lhv1b1.ConditionStatusTrue,
									},
									"1": {
										Type:   lhv1b1.DiskConditionTypeSchedulable,
										Status: lhv1b1.ConditionStatusTrue,
									},
								},
							},
							"disk-1": {
								StorageScheduled: 101,
								StorageAvailable: 50,
								Conditions: map[string]lhv1b1.Condition{
									"0": {
										Type:   lhv1b1.DiskConditionTypeReady,
										Status: lhv1b1.ConditionStatusTrue,
									},
									"1": {
										Type:   lhv1b1.DiskConditionTypeSchedulable,
										Status: lhv1b1.ConditionStatusTrue,
									},
								},
							},
						},
						Conditions: map[string]lhv1b1.Condition{
							"0": {
								Type:   lhv1b1.NodeConditionTypeReady,
								Status: lhv1b1.ConditionStatusTrue,
							},
							"1": {
								Type:   lhv1b1.NodeConditionTypeSchedulable,
								Status: lhv1b1.ConditionStatusTrue,
							},
						},
					},
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			scheme := runtime.NewScheme()
			lhv1b1.AddToScheme(scheme)
			cli := fake.NewClientBuilder().WithScheme(scheme).WithObjects(tt.objects...).Build()
			result, err := unhealthyNodes(context.Background(), discardLogger, cli)
			assert.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_nodeIs(t *testing.T) {
	for _, tt := range []struct {
		name      string
		expected  bool
		condition string
		node      lhv1b1.Node
	}{
		{
			name:      "if condition is not found then returns false",
			expected:  false,
			condition: "DiskConditionReasonDiskNotReady",
			node: lhv1b1.Node{
				Status: lhv1b1.NodeStatus{
					Conditions: map[string]lhv1b1.Condition{
						"foo": {
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
			condition: lhv1b1.NodeConditionTypeReady,
			node: lhv1b1.Node{
				Status: lhv1b1.NodeStatus{
					Conditions: map[string]lhv1b1.Condition{
						"0": {
							Type:   "foo",
							Status: lhv1b1.ConditionStatusFalse,
						},
						"1": {
							Type:   "bar",
							Status: lhv1b1.ConditionStatusFalse,
						},
						"2": {
							Type:   lhv1b1.NodeConditionTypeReady,
							Status: lhv1b1.ConditionStatusTrue,
						},
						"3": {
							Type:   "baz",
							Status: lhv1b1.ConditionStatusFalse,
						},
					},
				},
			},
		},
		{
			name:      "condition is found and status is true then returns true",
			expected:  true,
			condition: lhv1b1.NodeConditionTypeReady,
			node: lhv1b1.Node{
				Status: lhv1b1.NodeStatus{
					Conditions: map[string]lhv1b1.Condition{
						"": {
							Type:   lhv1b1.NodeConditionTypeReady,
							Status: lhv1b1.ConditionStatusTrue,
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
