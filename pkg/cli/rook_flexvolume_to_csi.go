package cli

import (
	"log"
	"os"

	"github.com/replicatedhq/kurl/pkg/rook"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewRookFlexvolumeToCSI(_ CLI) *cobra.Command {
	var opts rook.FlexvolumeToCSIOpts

	cmd := &cobra.Command{
		Use:   "flexvolume-to-csi",
		Short: "Converts Rook Flex volumes to Ceph-CSI volumes.",
		RunE: func(cmd *cobra.Command, _ []string) error {
			clientConfig := config.GetConfigOrDie()
			clientset := kubernetes.NewForConfigOrDie(clientConfig)

			logger := log.New(os.Stdout, "", 0)

			err := rook.FlexvolumeToCSI(cmd.Context(), logger, clientset, clientConfig, opts)
			return err
		},
		SilenceUsage: true,
	}

	cmd.Flags().StringVar(&opts.SourceStorageClass, "source-sc", "", "storage class name to migrate from")
	cmd.MarkFlagRequired("source-sc")
	cmd.Flags().StringVar(&opts.DestinationStorageClass, "destination-sc", "", "storage class name to migrate to")
	cmd.MarkFlagRequired("destination-sc")
	cmd.Flags().StringVar(&opts.NodeName, "node", "", "the node on which to run the migration (the pv migrator binary must be present on this node)")
	cmd.MarkFlagRequired("node")
	cmd.Flags().StringVar(&opts.PVMigratorBinPath, "pv-migrator-bin-path", "", "path to the pv migrator binary")
	cmd.MarkFlagRequired("pv-migrator-bin-path")
	cmd.Flags().StringVar(&opts.CephMigratorImage, "ceph-migrator-image", "", "image for the pv migrator container")
	cmd.MarkFlagRequired("ceph-migrator-image")

	return cmd
}
