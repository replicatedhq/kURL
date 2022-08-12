package cli

import (
	"github.com/replicatedhq/kurl/pkg/rook"
	"github.com/spf13/cobra"
	"os"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewHostpathToBlockCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "hostpath-to-block",
		Short: "Migrates rook hostpath data to block device volumes, changing the rook cluster config if needed",
		RunE: func(cmd *cobra.Command, args []string) error {
			k8sConfig := config.GetConfigOrDie()

			rook.InitWriter(os.Stdout)

			err := rook.HostpathToOsd(k8sConfig)
			return err
		},
	}
	return cmd
}
