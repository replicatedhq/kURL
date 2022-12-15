package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"

	clusterspace "github.com/replicatedhq/kurl/pkg/cluster/space"
	"github.com/replicatedhq/kurl/pkg/k8sutil"
	"github.com/replicatedhq/kurl/pkg/version"
	"github.com/replicatedhq/pvmigrate/pkg/migrate"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

const openEBSLocalProvisioner = "openebs.io/local"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	var skipFreeSpaceCheck bool
	var skipPvAccessModeCheck bool
	var dryRun bool
	var opts migrate.Options
	var printVersion bool
	flag.StringVar(&opts.SourceSCName, "source-sc", "", "storage provider name to migrate from")
	flag.StringVar(&opts.DestSCName, "dest-sc", "", "storage provider name to migrate to")
	flag.StringVar(&opts.RsyncImage, "rsync-image", "eeacms/rsync:2.3", "the image to use to copy PVCs - must have 'rsync' on the path")
	flag.StringVar(&opts.Namespace, "namespace", "", "only migrate PVCs within this namespace")
	flag.BoolVar(&opts.SetDefaults, "set-defaults", false, "change default storage class from source to dest")
	flag.BoolVar(&opts.VerboseCopy, "verbose-copy", false, "show output from the rsync command used to copy data between PVCs")
	flag.BoolVar(&opts.SkipSourceValidation, "skip-source-validation", false, "migrate from PVCs using a particular StorageClass name, even if that StorageClass does not exist")
	flag.BoolVar(&skipFreeSpaceCheck, "skip-free-space-check", false, "skips the check for storage free space prior to running the migrations")
	flag.BoolVar(&skipPvAccessModeCheck, "skip-pv-access-mode-check", false, "skips the volume access modes checks prior to running the migrations")
	flag.BoolVar(&dryRun, "dry-run", false, "run validation checks without running the migrations")
	flag.BoolVar(&printVersion, "version", false, "Print the version of the client")
	flag.IntVar(&opts.PodReadyTimeout, "pod-ready-timeout", 90, "length of time to wait (in seconds) for volume validation pod(s) to go into Ready phase")

	flag.Parse()

	if printVersion {
		fmt.Printf("Running pvmigrate build:\n")
		version.Print()
		os.Exit(0)
	}

	logger := log.New(os.Stdout, "", 0)
	cfg, err := config.GetConfig()
	if err != nil {
		logger.Printf("failed to get config: %s\n", err.Error())
		os.Exit(1)
	}

	cli, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		logger.Printf("failed to create kubernetes clientset: %s\n", err.Error())
		os.Exit(1)
	}

	if !skipFreeSpaceCheck || dryRun {
		if err := checkFreeSpace(ctx, logger, cfg, cli, opts); err != nil {
			logger.Printf("failed to check cluster free space: %s", err)
			os.Exit(1)
		}
	}

	if !skipPvAccessModeCheck || dryRun {
		unsupportedPVCs, err := validatePVAccessMode(ctx, logger, cfg, cli, opts)
		if err != nil {
			logger.Printf("failed to validate access modes for destination storage provider %s: %s", opts.DestSCName, err)
			os.Exit(1)
		}

		if len(unsupportedPVCs) != 0 {
			logger.Printf("PVC Access Mode Validation Failed: there are PVCs for storage class %s that cannot be mounted using the destination storage class %s.", opts.SourceSCName, opts.DestSCName)
			migrate.PrintPVAccessModeErrors(unsupportedPVCs)
			os.Exit(0)
		}
	}

	if !dryRun {
		if err = migrate.Migrate(ctx, logger, cli, opts); err != nil {
			fmt.Printf("%s\n", err.Error())
			os.Exit(1)
		}
	}
}

func validatePVAccessMode(ctx context.Context, logger *log.Logger, cfg *rest.Config, cli kubernetes.Interface, opts migrate.Options) (map[string]map[string]migrate.PVCError, error) {
	pvm, err := migrate.NewPVMigrator(cfg, logger, opts.SourceSCName, opts.DestSCName, opts.PodReadyTimeout)
	if err != nil {
		return nil, fmt.Errorf("failed to create PVMigrator type: %s", err)
	}

	srcPVs, err := k8sutil.PVSByStorageClass(ctx, cli, opts.SourceSCName)
	if err != nil {
		return nil, fmt.Errorf("failed to get volumes using storage class %s: %w", opts.SourceSCName, err)
	}
	unsupportedPVCs, err := pvm.ValidateVolumeAccessModes(srcPVs)
	if err != nil {
		return nil, fmt.Errorf("failed to validate volume access modes for destination storage class %s", opts.DestSCName)
	}

	return unsupportedPVCs, nil
}

func checkFreeSpace(ctx context.Context, logger *log.Logger, cfg *rest.Config, cli kubernetes.Interface, opts migrate.Options) error {
	logger.Printf("Checking if there is enough space to complete the storage migration")
	sclasses, err := cli.StorageV1().StorageClasses().List(ctx, metav1.ListOptions{})
	if err != nil {
		return fmt.Errorf("failed to get storage classes: %w", err)
	}

	var srcProvisioner string
	var dstProvisioner string
	for _, sc := range sclasses.Items {
		if sc.Name == opts.SourceSCName {
			srcProvisioner = sc.Provisioner
		}
		if sc.Name == opts.DestSCName {
			dstProvisioner = sc.Provisioner
		}
	}

	// we skip free space check if any of the provided storage classes don't exist.
	if srcProvisioner == "" || dstProvisioner == "" {
		return nil
	}

	if dstProvisioner == openEBSLocalProvisioner {
		dfchecker, err := clusterspace.NewOpenEBSDiskSpaceValidator(cfg, logger, opts.RsyncImage, opts.SourceSCName, opts.DestSCName)
		if err != nil {
			return fmt.Errorf("failed to create openebs free space checker: %w", err)
		}

		nodes, err := dfchecker.NodesWithoutSpace(ctx)
		if err != nil {
			return fmt.Errorf("failed to check nodes free space: %w", err)
		}

		if len(nodes) == 0 {
			return nil
		}

		return fmt.Errorf("some nodes do not have enough disk space for the migration: %s", strings.Join(nodes, ","))
	}

	rookProvisioners := map[string]bool{
		"rook-ceph.rbd.csi.ceph.com":    true,
		"rook-ceph.cephfs.csi.ceph.com": true,
	}
	if _, ok := rookProvisioners[dstProvisioner]; ok {
		dfchecker, err := clusterspace.NewRookDiskSpaceValidator(cfg, logger, opts.SourceSCName, opts.DestSCName)
		if err != nil {
			return fmt.Errorf("failed to create Rook/Ceph free space checker: %w", err)
		}

		hasSpace, err := dfchecker.HasEnoughDiskSpace(ctx)
		if err != nil {
			return fmt.Errorf("failed to check Rook/Ceph free space: %w", err)
		}

		if hasSpace {
			return nil
		}

		return fmt.Errorf("not enough space in Ceph to migrate data")
	}

	logger.Printf("Skipping disk space check, provisioner %s not supported.", dstProvisioner)
	return nil
}
