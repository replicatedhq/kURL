package clusterspace

import (
	"context"
	"fmt"
	"log"

	"code.cloudfoundry.org/bytefmt"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"

	"github.com/replicatedhq/kurl/pkg/k8sutil"
)

// OpenEBSDiskSpaceValidator checks if we have enough disk space on the cluster to migrate volumes to openebs.
type OpenEBSDiskSpaceValidator struct {
	freeSpaceGetter *OpenEBSFreeDiskSpaceGetter
	kcli            kubernetes.Interface
	log             *log.Logger
	srcSC           string
}

// hasEnoughSpace calculates if the openebs volume is capable of holding the provided reserved
// amount of bytes. if the openebs volume is part of the root filesystem then we decrease 15%
// of its space. returns the effective free space as well.
func (o *OpenEBSDiskSpaceValidator) hasEnoughSpace(vol OpenEBSVolume, reserved int64) (int64, bool) {
	total := float64(vol.Free + vol.Used)
	if vol.RootVolume {
		total *= 0.85
	}
	free := int64(total) - vol.Used
	return free, free > reserved
}

// NodesWithoutSpace check verifies if we have enough disk space to execute the migration. returns a list of nodes
// where the migration can't execute due to a possible lack of disk space.
func (o *OpenEBSDiskSpaceValidator) NodesWithoutSpace(ctx context.Context) ([]string, error) {
	o.log.Printf("Analyzing reserved and free disk space per node...")
	reservedPerNode, reservedDetached, err := k8sutil.PVSReservationPerNode(ctx, o.kcli, o.srcSC)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate reserved disk space per node: %w", err)
	}

	volumes, err := o.freeSpaceGetter.OpenEBSVolumes(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to calculate available disk space per node: %w", err)
	}

	faultyNodes := map[string]bool{}
	for node, vol := range volumes {
		var ok bool
		var free int64
		if free, ok = o.hasEnoughSpace(vol, reservedPerNode[node]); ok {
			continue
		}

		var reservedMsg string
		if vol.RootVolume {
			reservedMsg = "(15% of the root disk is reserved to prevent DiskPressure evictions)"
		}

		faultyNodes[node] = true
		o.log.Printf(
			"Node %q has %s available, which is less than the %s that would be migrated from the %q storage class %s",
			node,
			bytefmt.ByteSize(uint64(free)),
			bytefmt.ByteSize(uint64(reservedPerNode[node])),
			o.srcSC,
			reservedMsg,
		)
	}

	if reservedDetached != 0 {
		// XXX we make sure that the detached reserved space can be migrated to
		// *any* of the nodes as we don't know where the migration pod will be
		// scheduled.
		o.log.Printf(
			"Amount of detached PVs reservations (%q storage class): %s",
			o.srcSC,
			bytefmt.ByteSize(uint64(reservedDetached)),
		)

		for node, vol := range volumes {
			vol.Used += reservedPerNode[node]
			vol.Free -= reservedPerNode[node]
			if free, hasSpace := o.hasEnoughSpace(vol, reservedDetached); !hasSpace {
				if free < 0 {
					free = 0
				}
				o.log.Printf(
					"Node %q has %s left (after migrating reserved storage), "+
						"failed to host extra %s of detached PVs",
					node,
					bytefmt.ByteSize(uint64(free)),
					bytefmt.ByteSize(uint64(reservedDetached)),
				)
				faultyNodes[node] = true
			}
		}
	}

	if len(faultyNodes) > 0 {
		var nodeNames []string
		for name := range faultyNodes {
			nodeNames = append(nodeNames, name)
		}
		return nodeNames, nil
	}

	o.log.Printf("Enough disk space found, moving on")
	return nil, nil
}

// NewOpenEBSDiskSpaceValidator returns a disk free analyser for openebs storage local volume provisioner.
func NewOpenEBSDiskSpaceValidator(cfg *rest.Config, log *log.Logger, image, srcSC, dstSC string) (*OpenEBSDiskSpaceValidator, error) {
	kcli, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create kubernetes client: %w", err)
	}

	if image == "" {
		return nil, fmt.Errorf("empty image")
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

	freeSpaceGetter, err := NewOpenEBSFreeDiskSpaceGetter(kcli, log, image, dstSC)
	if err != nil {
		return nil, fmt.Errorf("unable to create free space getter: %w", err)
	}

	return &OpenEBSDiskSpaceValidator{
		freeSpaceGetter: freeSpaceGetter,
		kcli:            kcli,
		log:             log,
		srcSC:           srcSC,
	}, nil
}
