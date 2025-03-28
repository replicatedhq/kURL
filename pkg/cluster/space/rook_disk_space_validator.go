package clusterspace

import (
	"context"
	"fmt"
	"log"

	"code.cloudfoundry.org/bytefmt"
	rookcli "github.com/rook/rook/pkg/client/clientset/versioned"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"

	"github.com/replicatedhq/kurl/pkg/k8sutil"
)

const (
	namespace = "rook-ceph"
)

// RookDiskSpaceValidator checks if we have enough disk space to migrate volumes to rook.
type RookDiskSpaceValidator struct {
	kcli            kubernetes.Interface
	freeSpaceGetter *RookFreeDiskSpaceGetter
	log             *log.Logger
	srcSC           string
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

// HasEnoughDiskSpace verifies if there is enough ceph disk space to migrate from the source storage class.
func (r *RookDiskSpaceValidator) HasEnoughDiskSpace(ctx context.Context) (bool, error) {
	r.log.Print("Analysing reserved and free Ceph disk space...")

	free, err := r.freeSpaceGetter.GetFreeSpace(ctx)
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

	freeSpaceGetter, err := NewRookFreeDiskSpaceGetter(kcli, rcli, dstSC)
	if err != nil {
		return nil, fmt.Errorf("failed to initiate rook volume getter: %w", err)
	}

	return &RookDiskSpaceValidator{
		kcli:            kcli,
		freeSpaceGetter: freeSpaceGetter,
		log:             log,
		srcSC:           srcSC,
	}, nil
}
