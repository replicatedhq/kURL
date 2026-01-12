package clusterspace

import (
	"context"
	"strings"
	"testing"

	rookv1 "github.com/rook/rook/pkg/apis/ceph.rook.io/v1"
	rookfake "github.com/rook/rook/pkg/client/clientset/versioned/fake"
	storagev1 "k8s.io/api/storage/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/fake"
)

func Test_getPoolAndClusterName(t *testing.T) {
	for _, tt := range []struct {
		name   string
		scname string
		pname  string
		cname  string
		err    string
		sc     *storagev1.StorageClass
	}{
		{
			name:   "should be able to find pool and cluster name",
			scname: "test",
			pname:  "poolname",
			cname:  "clustername",
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
			name:   "should fail if storage class does not exist",
			err:    "failed to get storage class test",
			scname: "test",
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
			name:   "should fail if no pool name is present in the storage class",
			scname: "test",
			err:    "failed to read storage class test pool/cluster",
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
			name:   "should fail if no cluster name is present in the storage class",
			scname: "test",
			err:    "failed to read storage class test pool/cluster",
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
			kcli := fake.NewClientset(tt.sc)
			rchecker := RookFreeDiskSpaceGetter{scname: tt.scname, kcli: kcli}
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

func TestGetFreeSpace(t *testing.T) {
	for _, tt := range []struct {
		name     string
		scname   string
		err      string
		expected int64
		sc       *storagev1.StorageClass
		pool     *rookv1.CephBlockPool
		cluster  *rookv1.CephCluster
	}{
		{
			name:     "should be able to parse ceph free space",
			scname:   "test",
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
			scname:   "test",
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
			name:   "should fail when the ceph pool does not exist",
			scname: "test",
			err:    "failed to get pool",
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
			name:   "should fail with invalid zeroed ceph pool replicas",
			scname: "test",
			err:    "pool replica size is zeroed",
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
			name:   "should fail when ceph cluster is not found",
			scname: "test",
			err:    "failed to get ceph cluster",
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
			name:   "should failed if no ceph status is present",
			scname: "test",
			err:    "failed to read ceph status (nil)",
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
			kcli := fake.NewClientset(tt.sc)
			rcli := rookfake.NewSimpleClientset(tt.pool, tt.cluster)
			rchecker := RookFreeDiskSpaceGetter{scname: tt.scname, kcli: kcli, rcli: rcli}
			result, err := rchecker.GetFreeSpace(context.Background())
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
