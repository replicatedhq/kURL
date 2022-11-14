package clusterspace

import (
	"context"
	"io"
	"log"
	"strings"
	"testing"

	rookv1 "github.com/rook/rook/pkg/apis/ceph.rook.io/v1"
	rookfake "github.com/rook/rook/pkg/client/clientset/versioned/fake"
	corev1 "k8s.io/api/core/v1"
	storagev1 "k8s.io/api/storage/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	"k8s.io/client-go/rest"
)

func TestRookCheck(t *testing.T) {
	for _, tt := range []struct {
		name        string
		coreObjects []runtime.Object
		rookObjects []runtime.Object
		srcSC       string
		err         string
	}{
		{
			name:  "should be able evaluate the disk space",
			srcSC: "default",
			coreObjects: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "default",
					},
					Parameters: map[string]string{
						"pool":      "poolname",
						"clusterID": "clustername",
					},
				},
			},
			rookObjects: []runtime.Object{
				&rookv1.CephBlockPool{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "poolname",
						Namespace: namespace,
					},
					Spec: rookv1.NamedBlockPoolSpec{
						PoolSpec: rookv1.PoolSpec{
							Replicated: rookv1.ReplicatedSpec{
								Size: 1,
							},
						},
					},
				},
				&rookv1.CephCluster{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "clustername",
						Namespace: namespace,
					},
					Status: rookv1.ClusterStatus{
						CephStatus: &rookv1.CephStatus{
							Capacity: rookv1.Capacity{
								AvailableBytes: 100,
							},
						},
					},
				},
			},
		},
		{
			name:  "should fail to check reserved space with an invalid src storage class",
			srcSC: "i-do-not-exist",
			err:   `storageclasses.storage.k8s.io "i-do-not-exist" not found`,
			coreObjects: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "default",
					},
					Parameters: map[string]string{
						"pool":      "poolname",
						"clusterID": "clustername",
					},
				},
			},
			rookObjects: []runtime.Object{
				&rookv1.CephBlockPool{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "poolname",
						Namespace: namespace,
					},
					Spec: rookv1.NamedBlockPoolSpec{
						PoolSpec: rookv1.PoolSpec{
							Replicated: rookv1.ReplicatedSpec{
								Size: 1,
							},
						},
					},
				},
				&rookv1.CephCluster{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "clustername",
						Namespace: namespace,
					},
					Status: rookv1.ClusterStatus{
						CephStatus: &rookv1.CephStatus{
							Capacity: rookv1.Capacity{
								AvailableBytes: 100,
							},
						},
					},
				},
			},
		},
		{
			name:  "should fail to check free space when the pool is missing",
			err:   "failed to verify free space: failed to get pool poolname",
			srcSC: "default",
			coreObjects: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "default",
					},
					Parameters: map[string]string{
						"pool":      "poolname",
						"clusterID": "clustername",
					},
				},
			},
			rookObjects: []runtime.Object{
				&rookv1.CephCluster{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "clustername",
						Namespace: namespace,
					},
					Status: rookv1.ClusterStatus{
						CephStatus: &rookv1.CephStatus{
							Capacity: rookv1.Capacity{
								AvailableBytes: 100,
							},
						},
					},
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			logger := log.New(io.Discard, "", 0)
			rcli := rookfake.NewSimpleClientset(tt.rookObjects...)
			kcli := fake.NewSimpleClientset(tt.coreObjects...)

			checker := RookChecker{
				kcli:  kcli,
				rcli:  rcli,
				log:   logger,
				srcSC: tt.srcSC,
				dstSC: "default",
			}

			_, err := checker.HasEnoughDiskSpace(context.Background())
			if err != nil {
				if len(tt.err) == 0 {
					t.Errorf("unexpected error: %s", err)
				} else if !strings.Contains(err.Error(), tt.err) {
					t.Errorf("expecting %q, %q received instead", tt.err, err)
				}
				return
			}

			if len(tt.err) > 0 {
				t.Errorf("expecting error %q, nil received instead", tt.err)
			}
		})
	}

}

func Test_reservedSpace(t *testing.T) {
	for _, tt := range []struct {
		name     string
		srcSC    string
		err      string
		expected int64
		objs     []runtime.Object
	}{
		{
			name:     "should pass with a detached volume",
			srcSC:    "test",
			expected: 1000000000,
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "test",
					},
					Parameters: map[string]string{
						"pool":      "poolname",
						"clusterID": "clustername",
					},
				},
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "namespace",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pv",
						Namespace: "namespace",
					},
					Spec: corev1.PersistentVolumeSpec{
						StorageClassName: "test",
						ClaimRef: &corev1.ObjectReference{
							Namespace: "namespace",
							Name:      "pvc",
						},
						Capacity: corev1.ResourceList{
							corev1.ResourceStorage: resource.MustParse("1G"),
						},
					},
				},
			},
		},
		{
			name:     "should pass with multiple detached pvc",
			srcSC:    "test",
			expected: 5000000000,
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "test",
					},
					Parameters: map[string]string{
						"pool":      "poolname",
						"clusterID": "clustername",
					},
				},
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "namespace",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pv",
						Namespace: "namespace",
					},
					Spec: corev1.PersistentVolumeSpec{
						StorageClassName: "test",
						ClaimRef: &corev1.ObjectReference{
							Namespace: "namespace",
							Name:      "pvc",
						},
						Capacity: corev1.ResourceList{
							corev1.ResourceStorage: resource.MustParse("2G"),
						},
					},
				},
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc0",
						Namespace: "namespace",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pv0",
						Namespace: "namespace",
					},
					Spec: corev1.PersistentVolumeSpec{
						StorageClassName: "test",
						ClaimRef: &corev1.ObjectReference{
							Namespace: "namespace",
							Name:      "pvc0",
						},
						Capacity: corev1.ResourceList{
							corev1.ResourceStorage: resource.MustParse("3G"),
						},
					},
				},
			},
		},
		{
			name:     "should pass and return the sum of detached and attached pvc",
			srcSC:    "test",
			expected: 10000000000,
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "test",
					},
					Parameters: map[string]string{
						"pool":      "poolname",
						"clusterID": "clustername",
					},
				},
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "namespace",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pv",
						Namespace: "namespace",
					},
					Spec: corev1.PersistentVolumeSpec{
						StorageClassName: "test",
						ClaimRef: &corev1.ObjectReference{
							Namespace: "namespace",
							Name:      "pvc",
						},
						Capacity: corev1.ResourceList{
							corev1.ResourceStorage: resource.MustParse("5G"),
						},
					},
				},
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc0",
						Namespace: "namespace",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pv0",
						Namespace: "namespace",
					},
					Spec: corev1.PersistentVolumeSpec{
						StorageClassName: "test",
						ClaimRef: &corev1.ObjectReference{
							Namespace: "namespace",
							Name:      "pvc0",
						},
						Capacity: corev1.ResourceList{
							corev1.ResourceStorage: resource.MustParse("5G"),
						},
					},
				},
				&corev1.Pod{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pod",
						Namespace: "namespace",
					},
					Spec: corev1.PodSpec{
						Volumes: []corev1.Volume{
							{
								Name: "vol",
								VolumeSource: corev1.VolumeSource{
									PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
										ClaimName: "pvc0",
									},
								},
							},
						},
					},
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			kcli := fake.NewSimpleClientset(tt.objs...)
			rchecker := RookChecker{srcSC: tt.srcSC, kcli: kcli}
			result, err := rchecker.reservedSpace(context.Background())
			if err != nil {
				if len(tt.err) == 0 {
					t.Errorf("unexpected error: %s", err)
				} else if !strings.Contains(err.Error(), tt.err) {
					t.Errorf("expecting %q, %q received instead", tt.err, err)
				}
				return
			}

			if len(tt.err) > 0 {
				t.Errorf("expecting error %q, nil received instead", tt.err)
			}

			if result != tt.expected {
				t.Errorf("expecting reserved space %v, received %v", tt.expected, result)
			}
		})
	}
}

func Test_freeSpace(t *testing.T) {
	for _, tt := range []struct {
		name     string
		dstSC    string
		err      string
		expected int64
		sc       *storagev1.StorageClass
		pool     *rookv1.CephBlockPool
		cluster  *rookv1.CephCluster
	}{
		{
			name:     "should be able to parse ceph free space",
			dstSC:    "test",
			expected: 100,
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test",
				},
				Parameters: map[string]string{
					"pool":      "poolname",
					"clusterID": "clustername",
				},
			},
			pool: &rookv1.CephBlockPool{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "poolname",
					Namespace: namespace,
				},
				Spec: rookv1.NamedBlockPoolSpec{
					PoolSpec: rookv1.PoolSpec{
						Replicated: rookv1.ReplicatedSpec{
							Size: 1,
						},
					},
				},
			},
			cluster: &rookv1.CephCluster{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "clustername",
					Namespace: namespace,
				},
				Status: rookv1.ClusterStatus{
					CephStatus: &rookv1.CephStatus{
						Capacity: rookv1.Capacity{
							AvailableBytes: 100,
						},
					},
				},
			},
		},
		{
			name:     "should pass with pool configured for two replicas",
			dstSC:    "test",
			expected: 50,
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test",
				},
				Parameters: map[string]string{
					"pool":      "poolname",
					"clusterID": "clustername",
				},
			},
			pool: &rookv1.CephBlockPool{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "poolname",
					Namespace: namespace,
				},
				Spec: rookv1.NamedBlockPoolSpec{
					PoolSpec: rookv1.PoolSpec{
						Replicated: rookv1.ReplicatedSpec{
							Size: 2,
						},
					},
				},
			},
			cluster: &rookv1.CephCluster{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "clustername",
					Namespace: namespace,
				},
				Status: rookv1.ClusterStatus{
					CephStatus: &rookv1.CephStatus{
						Capacity: rookv1.Capacity{
							AvailableBytes: 100,
						},
					},
				},
			},
		},
		{
			name:  "should fail when the ceph pool does not exist",
			dstSC: "test",
			err:   "failed to get pool",
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test",
				},
				Parameters: map[string]string{
					"pool":      "poolname",
					"clusterID": "clustername",
				},
			},
			pool: &rookv1.CephBlockPool{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "another-poolname",
					Namespace: namespace,
				},
				Spec: rookv1.NamedBlockPoolSpec{
					PoolSpec: rookv1.PoolSpec{
						Replicated: rookv1.ReplicatedSpec{
							Size: 2,
						},
					},
				},
			},
			cluster: &rookv1.CephCluster{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "clustername",
					Namespace: namespace,
				},
				Status: rookv1.ClusterStatus{
					CephStatus: &rookv1.CephStatus{
						Capacity: rookv1.Capacity{
							AvailableBytes: 100,
						},
					},
				},
			},
		},
		{
			name:  "should fail with invalid zeroed ceph pool replicas",
			dstSC: "test",
			err:   "pool replica size is zeroed",
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test",
				},
				Parameters: map[string]string{
					"pool":      "poolname",
					"clusterID": "clustername",
				},
			},
			pool: &rookv1.CephBlockPool{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "poolname",
					Namespace: namespace,
				},
				Spec: rookv1.NamedBlockPoolSpec{
					PoolSpec: rookv1.PoolSpec{
						Replicated: rookv1.ReplicatedSpec{
							Size: 0,
						},
					},
				},
			},
			cluster: &rookv1.CephCluster{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "clustername",
					Namespace: namespace,
				},
				Status: rookv1.ClusterStatus{
					CephStatus: &rookv1.CephStatus{
						Capacity: rookv1.Capacity{
							AvailableBytes: 100,
						},
					},
				},
			},
		},
		{
			name:  "should fail when ceph cluster is not found",
			dstSC: "test",
			err:   "failed to get ceph cluster",
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test",
				},
				Parameters: map[string]string{
					"pool":      "poolname",
					"clusterID": "clustername",
				},
			},
			pool: &rookv1.CephBlockPool{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "poolname",
					Namespace: namespace,
				},
				Spec: rookv1.NamedBlockPoolSpec{
					PoolSpec: rookv1.PoolSpec{
						Replicated: rookv1.ReplicatedSpec{
							Size: 1,
						},
					},
				},
			},
			cluster: &rookv1.CephCluster{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "another-clustername",
					Namespace: namespace,
				},
				Status: rookv1.ClusterStatus{
					CephStatus: &rookv1.CephStatus{
						Capacity: rookv1.Capacity{
							AvailableBytes: 100,
						},
					},
				},
			},
		},
		{
			name:  "should failed if no ceph status is present",
			dstSC: "test",
			err:   "failed to read ceph status (nil)",
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test",
				},
				Parameters: map[string]string{
					"pool":      "poolname",
					"clusterID": "clustername",
				},
			},
			pool: &rookv1.CephBlockPool{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "poolname",
					Namespace: namespace,
				},
				Spec: rookv1.NamedBlockPoolSpec{
					PoolSpec: rookv1.PoolSpec{
						Replicated: rookv1.ReplicatedSpec{
							Size: 1,
						},
					},
				},
			},
			cluster: &rookv1.CephCluster{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "clustername",
					Namespace: namespace,
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			kcli := fake.NewSimpleClientset(tt.sc)
			rcli := rookfake.NewSimpleClientset(tt.pool, tt.cluster)
			rchecker := RookChecker{dstSC: tt.dstSC, kcli: kcli, rcli: rcli}
			result, err := rchecker.getFreeSpace(context.Background())
			if err != nil {
				if len(tt.err) == 0 {
					t.Errorf("unexpected error: %s", err)
				} else if !strings.Contains(err.Error(), tt.err) {
					t.Errorf("expecting %q, %q received instead", tt.err, err)
				}
				return
			}

			if len(tt.err) > 0 {
				t.Errorf("expecting error %q, nil received instead", tt.err)
			}

			if result != tt.expected {
				t.Errorf("expecting free space %v, received %v", tt.expected, result)
			}
		})
	}
}

func Test_getPoolAndClusterName(t *testing.T) {
	for _, tt := range []struct {
		name  string
		dstSC string
		pname string
		cname string
		err   string
		sc    *storagev1.StorageClass
	}{
		{
			name:  "should be able to find pool and cluster name",
			dstSC: "test",
			pname: "poolname",
			cname: "clustername",
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test",
				},
				Parameters: map[string]string{
					"pool":      "poolname",
					"clusterID": "clustername",
				},
			},
		},
		{
			name:  "should fail if storage class does not exist",
			err:   "failed to get storage class test",
			dstSC: "test",
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "default",
				},
				Parameters: map[string]string{
					"pool":      "poolname",
					"clusterID": "clustername",
				},
			},
		},
		{
			name:  "should fail if no pool name is present in the storage class",
			dstSC: "test",
			err:   "failed to read storage class test pool/cluster",
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test",
				},
				Parameters: map[string]string{
					"clusterID": "clustername",
				},
			},
		},
		{
			name:  "should fail if no cluster name is present in the storage class",
			dstSC: "test",
			err:   "failed to read storage class test pool/cluster",
			sc: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "test",
				},
				Parameters: map[string]string{
					"pool": "poolname",
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			kcli := fake.NewSimpleClientset(tt.sc)
			rchecker := RookChecker{dstSC: tt.dstSC, kcli: kcli}
			pname, cname, err := rchecker.getPoolAndClusterNames(context.Background())
			if err != nil {
				if len(tt.err) == 0 {
					t.Errorf("unexpected error: %s", err)
				} else if !strings.Contains(err.Error(), tt.err) {
					t.Errorf("expecting %q, %q received instead", tt.err, err)
				}
				return
			}

			if len(tt.err) > 0 {
				t.Errorf("expecting error %q, nil received instead", tt.err)
			}

			if pname != tt.pname {
				t.Errorf("expecting pool name %v, received %v", tt.pname, pname)
			}

			if cname != tt.cname {
				t.Errorf("expecting cluster name %v, received %v", tt.cname, cname)
			}
		})
	}

}

func TestNewRookChecker(t *testing.T) {
	// test empty logger
	_, err := NewRookChecker(&rest.Config{}, nil, "src", "dst")
	if err == nil || err.Error() != "no logger provided" {
		t.Errorf("expected failure creating object: %v", err)
	}

	logger := log.New(io.Discard, "", 0)

	// test src storage class
	_, err = NewRookChecker(&rest.Config{}, logger, "", "dst")
	if err == nil || err.Error() != "empty source storage class" {
		t.Errorf("expected failure creating object: %v", err)
	}

	// test empty dst sc
	_, err = NewRookChecker(&rest.Config{}, logger, "src", "")
	if err == nil || err.Error() != "empty destination storage class" {
		t.Errorf("expected failure creating object: %v", err)
	}

	// happy path
	_, err = NewRookChecker(&rest.Config{}, logger, "src", "dst")
	if err != nil {
		t.Errorf("unexpected failure creating object: %v", err)
	}
}
