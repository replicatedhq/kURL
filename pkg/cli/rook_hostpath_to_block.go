package cli

import (
	"github.com/replicatedhq/kurl/pkg/rook"
	"github.com/spf13/cobra"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewHostpathToBlockCmd(_ CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "hostpath-to-block",
		Short: "Migrates rook hostpath data to block device volumes, changing the rook cluster config if needed",
		RunE: func(cmd *cobra.Command, _ []string) error {
			k8sConfig := config.GetConfigOrDie()

			rook.InitWriter(cmd.OutOrStdout())

			err := rook.HostpathToOsd(cmd.Context(), k8sConfig)
			return err
		},
		SilenceUsage: true,
	}

	return cmd
}
