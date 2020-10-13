package run

import (
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner"
	"github.com/spf13/cobra"
)

func CleanCmd() *cobra.Command {
	return &cobra.Command{
		Use:     "clean",
		Aliases: []string{"r", "rm"},
		Short:   "Clean-up tasks",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runner.CleanUp()
		},
	}
}
