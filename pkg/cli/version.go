package cli

import (
	"github.com/replicatedhq/kurl/pkg/version"
	"github.com/spf13/cobra"
)

func NewVersionCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "version",
		Short: "Print the current version and exit",
		Long:  `Print the current version and exit`,
		RunE: func(cmd *cobra.Command, args []string) error {
			version.Fprint(cmd.OutOrStdout())
			return nil
		},
	}
	return cmd
}
