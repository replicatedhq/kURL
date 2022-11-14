package clusterspace

import (
	"context"
	"fmt"
	"log"

	"code.cloudfoundry.org/bytefmt"
	rookcli "github.com/rook/rook/pkg/client/clientset/versioned"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"

	"github.com/replicatedhq/kurl/pkg/k8sutil"
)

const (
	namespace = "rook-ceph"
)

// RookDiskSpaceValidator checks if we have enough disk space to migrate volumes to rook.
type RookDiskSpaceValidator struct {
	kcli  kubernetes.Interface
	rcli  rookcli.Interface
	cfg   *rest.Config
	log   *log.Logger
	srcSC string
	dstSC string
}

// getFreeSpace attempts to get the ceph free space. returns the number of available bytes.
func (r *RookDiskSpaceValidator) getFreeSpace(ctx context.Context) (int64, error) {
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

// reservedSpace returns the total size of all volumes using the source storage class (srcSC).
func (r *RookDiskSpaceValidator) reservedSpace(ctx context.Context) (int64, error) {
	usedPerNode, usedDetached, err := k8sutil.PVSReservationPerNode(ctx, r.kcli, r.srcSC)
	if err != nil {
		return 0, fmt.Errorf("failed to calculate used disk space per node: %w", err)
	}

	total := usedDetached
	for _, used := range usedPerNode {
		total += used
	}

	return total, nil
}

// getPoolAndClusterNames returns the replicapool and the rook cluster name a s specified in
// the destination storage class parameters property.
func (r *RookDiskSpaceValidator) getPoolAndClusterNames(ctx context.Context) (string, string, error) {
	var pname string
	var cname string

	sc, err := r.kcli.StorageV1().StorageClasses().Get(ctx, r.dstSC, metav1.GetOptions{})
	if err != nil {
		return "", "", fmt.Errorf("failed to get storage class %s: %w", r.dstSC, err)
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
		return "", "", fmt.Errorf("failed to read storage class %s pool/cluster", r.dstSC)
	}
	return pname, cname, nil
}

// Check verifies if there is enough ceph disk space to migrate from the source storage class.
func (r *RookDiskSpaceValidator) HasEnoughDiskSpace(ctx context.Context) (bool, error) {
	r.log.Print("Analysing reserved and free Ceph disk space...")

	free, err := r.getFreeSpace(ctx)
	if err != nil {
		return false, fmt.Errorf("failed to verify free space: %w", err)
	}

	reserved, err := r.reservedSpace(ctx)
	if err != nil {
		return false, fmt.Errorf("failed to calculate used space: %w", err)
	}

	r.log.Print("\n")
	r.log.Printf("Free space in Ceph: %s", bytefmt.ByteSize(uint64(free)))
	r.log.Printf("Reserved (%q storage class): %s", r.srcSC, bytefmt.ByteSize(uint64(reserved)))
	r.log.Print("\n")
	return free > reserved, nil
}

// NewRookDiskSpaceValidator returns a disk free analyser for rook storage provisioner.
func NewRookDiskSpaceValidator(cfg *rest.Config, log *log.Logger, srcSC, dstSC string) (*RookDiskSpaceValidator, error) {
	kcli, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create kubernetes client: %w", err)
	}

	rcli, err := rookcli.NewForConfig(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create rook client: %w", err)
	}

	if srcSC == "" {
		return nil, fmt.Errorf("empty source storage class")
	}
	if dstSC == "" {
		return nil, fmt.Errorf("empty destination storage class")
	}
	if log == nil {
		return nil, fmt.Errorf("no logger provided")
	}

	return &RookDiskSpaceValidator{
		kcli:  kcli,
		rcli:  rcli,
		cfg:   cfg,
		log:   log,
		srcSC: srcSC,
		dstSC: dstSC,
	}, nil
}
