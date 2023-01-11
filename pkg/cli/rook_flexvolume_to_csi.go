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
		RunE: func(cmd *cobra.Command, args []string) error {
			clientConfig := config.GetConfigOrDie()
			clientset := kubernetes.NewForConfigOrDie(clientConfig)

			logger := log.New(os.Stderr, "", 0)

			err := rook.FlexvolumeToCSI(cmd.Context(), clientset, clientConfig, logger, opts)
			return err
		},
		SilenceUsage: true,
	}

	cmd.Flags().StringVar(&opts.SourceStorageClass, "source-sc", "", "storage provider name to migrate from")
	cmd.MarkFlagRequired("source-sc")
	cmd.Flags().StringVar(&opts.DestinationStorageClass, "destination-sc", "", "storage provider name to migrate to")
	cmd.MarkFlagRequired("destination-sc")

	return cmd
}
