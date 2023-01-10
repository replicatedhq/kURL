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
		PreRunE: func(cmd *cobra.Command, args []string) error {
			if opts.KubeconfigPath == "" {
				if env := os.Getenv("KUBECONFIG"); env != "" {
					opts.KubeconfigPath = env
				}
			}
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			config := config.GetConfigOrDie()
			client := kubernetes.NewForConfigOrDie(config)

			logger := log.New(os.Stderr, "", 0)

			err := rook.FlexvolumeToCSI(cmd.Context(), client, logger, opts)
			return err
		},
		SilenceUsage: true,
	}

	cmd.Flags().StringVar(&opts.PVMigratorBinPath, "pv-migrator-bin-path", "", "path to ceph/pv-migrator binary")
	cmd.MarkFlagRequired("pv-migrator-bin-path")
	cmd.MarkFlagFilename("pv-migrator-bin-path")
	cmd.Flags().StringVar(&opts.SourceStorageClass, "source-sc", "", "storage provider name to migrate from")
	cmd.MarkFlagRequired("source-sc")
	cmd.Flags().StringVar(&opts.DestinationStorageClass, "destination-sc", "", "storage provider name to migrate to")
	cmd.MarkFlagRequired("destination-sc")
	cmd.Flags().StringVar(&opts.KubeconfigPath, "kubeconfig-path", "", "kubernetes config file path (default is in-cluster config)")
	cmd.MarkFlagFilename("kubeconfig-path")

	return cmd
}
