package cli

import (
	"fmt"

	"github.com/replicatedhq/kurl/pkg/host"
	"github.com/spf13/cobra"
)

func newHostProtectedidCmd(_ CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "protectedid",
		Short: "Prints the kURL host protected machine id",
		RunE: func(cmd *cobra.Command, _ []string) error {
			id, err := host.ProtectedID()
			if err != nil {
				return err
			}
			fmt.Fprintln(cmd.OutOrStdout(), id)
			return nil
		},
	}
	return cmd
}
