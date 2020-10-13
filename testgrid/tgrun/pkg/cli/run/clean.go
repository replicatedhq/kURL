package run

import (
	"fmt"

	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner"
	"github.com/spf13/cobra"
)

func CleanCmd() *cobra.Command {
	return &cobra.Command{
		Use:     "clean",
		Aliases: []string{"r", "rm"},
		Short:   "Clean-up tasks",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runCleanUp()
		},
	}
}

func runCleanUp() error {
	if err := runner.CleanUpPVs(); err != nil {
		fmt.Println("PV clean up ERROR: ", err)
	}
	if err := runner.CleanUpVMIs(); err != nil {
		fmt.Println("VMI clean up ERROR: ", err)
	}
	return nil
}
