package cli

import (
	"github.com/spf13/cobra"
)

const rootCmdLong = ``

// NewKurlCmd creates a CLI for the kURL custom Kubernetes distro creator
func NewKurlCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "kurl",
		Short: "A CLI for the kURL custom Kubernetes distro creator",
		Long:  rootCmdLong,
		PersistentPreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
	}

	cmd.PersistentFlags().Bool("debug", false, "enable debug logging")

	AddCommands(cmd, cli)

	return cmd
}
