package cli

import (
	"github.com/spf13/cobra"
)

func NewHostCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "host",
		Short: "Perform operations on the kURL host",
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
	}

	return cmd
}
