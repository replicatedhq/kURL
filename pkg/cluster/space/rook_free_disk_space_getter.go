package clusterspace

import (
	"context"
	"fmt"

	rookcli "github.com/rook/rook/pkg/client/clientset/versioned"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

type RookFreeDiskSpaceGetter struct {
	kcli   kubernetes.Interface
	rcli   rookcli.Interface
	scname string
}

// getPoolAndClusterNames returns the replicapool and the rook cluster name a s specified in
// the destination storage class parameters property.
func (r *RookFreeDiskSpaceGetter) getPoolAndClusterNames(ctx context.Context) (string, string, error) {
	var pname string
	var cname string

	sc, err := r.kcli.StorageV1().StorageClasses().Get(ctx, r.scname, metav1.GetOptions{})
	if err != nil {
		return "", "", fmt.Errorf("failed to get storage class %s: %w", r.scname, err)
	}

	for p, v := range sc.Parameters {
		switch p {
		case "pool":
			pname = v
		case "clusterID":
			cname = v
		}
	}

	if pname == "" || cname == "" {
		return "", "", fmt.Errorf("failed to read storage class %s pool/cluster", r.scname)
	}
	return pname, cname, nil
}

// GetFreeSpace attempts to get the ceph free space. returns the number of available bytes.
func (r *RookFreeDiskSpaceGetter) GetFreeSpace(ctx context.Context) (int64, error) {
	pname, cname, err := r.getPoolAndClusterNames(ctx)
	if err != nil {
		return 0, fmt.Errorf("failed to get ceph pool: %w", err)
	}

	pool, err := r.rcli.CephV1().CephBlockPools(namespace).Get(ctx, pname, metav1.GetOptions{})
	if err != nil {
		return 0, fmt.Errorf("failed to get pool %s: %w", pname, err)
	}

	// this should never happen but we better this than a division by zero.
	if pool.Spec.Replicated.Size == 0 {
		return 0, fmt.Errorf("pool replica size is zeroed")
	}

	cluster, err := r.rcli.CephV1().CephClusters(namespace).Get(ctx, cname, metav1.GetOptions{})
	if err != nil {
		return 0, fmt.Errorf("failed to get ceph cluster %s: %w", cname, err)
	}

	if cluster.Status.CephStatus == nil {
		return 0, fmt.Errorf("failed to read ceph status (nil)")
	}

	availint64 := int64(cluster.Status.CephStatus.Capacity.AvailableBytes)
	replicasint64 := int64(pool.Spec.Replicated.Size)
	return availint64 / replicasint64, nil
}

// NewRookFreeDiskSpaceGetter returns a disk free getter for rook storage provisioner.
func NewRookFreeDiskSpaceGetter(kcli kubernetes.Interface, rcli rookcli.Interface, scname string) (*RookFreeDiskSpaceGetter, error) {
	if scname == "" {
		return nil, fmt.Errorf("empty storage class")
	}
	return &RookFreeDiskSpaceGetter{
		kcli:   kcli,
		rcli:   rcli,
		scname: scname,
	}, nil
}
