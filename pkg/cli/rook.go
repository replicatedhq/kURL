package cli

import (
	"github.com/spf13/cobra"
)

func NewRookCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "rook",
		Short: "Perform operations on a rook-ceph installation within a kURL cluster",
		PersistentPreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
	}

	return cmd
}
