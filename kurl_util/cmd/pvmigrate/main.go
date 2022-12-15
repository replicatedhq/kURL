package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"time"

	clusterspace "github.com/replicatedhq/kurl/pkg/cluster/space"
	"github.com/replicatedhq/kurl/pkg/version"
	"github.com/replicatedhq/pvmigrate/pkg/migrate"
	"github.com/replicatedhq/pvmigrate/pkg/preflight"
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
	var skipPreflightValidation bool
	var preflightValidationOnly bool
	var printVersion bool
	var podReadyTimeout int
	var deletePVTimeout int
	var opts migrate.Options

	flag.StringVar(&opts.SourceSCName, "source-sc", "", "storage provider name to migrate from")
	flag.StringVar(&opts.DestSCName, "dest-sc", "", "storage provider name to migrate to")
	flag.StringVar(&opts.RsyncImage, "rsync-image", "eeacms/rsync:2.3", "the image to use to copy PVCs - must have 'rsync' on the path")
	flag.StringVar(&opts.Namespace, "namespace", "", "only migrate PVCs within this namespace")
	flag.BoolVar(&opts.SetDefaults, "set-defaults", false, "change default storage class from source to dest")
	flag.BoolVar(&opts.VerboseCopy, "verbose-copy", false, "show output from the rsync command used to copy data between PVCs")
	flag.BoolVar(&opts.SkipSourceValidation, "skip-source-validation", false, "migrate from PVCs using a particular StorageClass name, even if that StorageClass does not exist")
	flag.BoolVar(&skipFreeSpaceCheck, "skip-free-space-check", false, "skips the check for storage free space prior to running the migrations")
	flag.BoolVar(&printVersion, "version", false, "Print the version of the client")
	flag.IntVar(&podReadyTimeout, "pod-ready-timeout", 60, "length of time to wait (in seconds) for volume validation pod(s) to go into Ready phase")
	flag.IntVar(&deletePVTimeout, "delete-pv-timeout", 300, "length of time to wait (in seconds) for backing PV to be removed when temporary PVC is deleted")
	flag.BoolVar(&skipPreflightValidation, "skip-preflight-validation", false, "skips pre-migration validation")
	flag.BoolVar(&preflightValidationOnly, "preflight-validation-only", false, "skip the migration and run preflight validation only")

	flag.Parse()

	fmt.Printf("Running pvmigrate build:\n")
	version.Print()

	// if --version flag is set, exit
	if printVersion {
		os.Exit(0)
	}

	// update migrate options with flag values
	opts.PodReadyTimeout = time.Duration(podReadyTimeout) * time.Second
	opts.DeletePVTimeout = time.Duration(deletePVTimeout) * time.Second

	logger := log.New(os.Stderr, "", 0)
	cfg, err := config.GetConfig()
	if err != nil {
		logger.Fatalf("failed to get config: %s\n", err.Error())
	}

	cli, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		logger.Fatalf("failed to create kubernetes clientset: %s\n", err.Error())
	}

	if !skipFreeSpaceCheck {
		if err := checkFreeSpace(ctx, logger, cfg, cli, opts); err != nil {
			logger.Fatalf("failed to check cluster free space: %s", err)
		}
	}

	if !skipPreflightValidation {
		logger.Printf("Running preflight migration checks (can take a couple of minutes to complete)")
		failures, err := preflight.Validate(ctx, logger, cli, opts)
		if err != nil {
			logger.Fatalf("failed to run preflight validation checks: %s", err)
		}

		if len(failures) != 0 {
			preflight.PrintValidationFailures(os.Stdout, failures)
			os.Exit(1)
		}
	}

	if !preflightValidationOnly {
		if err = migrate.Migrate(ctx, logger, cli, opts); err != nil {
			logger.Fatalf("%s\n", err.Error())
		}
	}
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
