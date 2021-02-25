package cli

import (
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

const rootCmdLong = ``

func RootCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "kurl",
		Short: "A CLI for the kURL custom Kubernetes distro creator",
		Long:  rootCmdLong,
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			return viper.BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			return viper.BindPFlags(cmd.Flags())
		},
	}

	cmd.AddCommand(VersionCmd())
	cmd.AddCommand(PreflightCmd())

	return cmd
}
