package cli

import (
	"github.com/spf13/cobra"
)

func NewClusterCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "cluster",
		Short: "Perform operations on the kURL cluster",
		PersistentPreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
	}

	return cmd
}
