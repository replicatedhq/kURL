package cli

import (
	"fmt"

	"github.com/replicatedhq/kurl/pkg/host"
	"github.com/spf13/cobra"
)

func newHostnameCmd(_ CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "hostname",
		Short: "Prints the kURL hostname",
		RunE: func(cmd *cobra.Command, _ []string) error {
			id, err := host.GetHostname()
			if err != nil {
				return err
			}
			fmt.Fprintln(cmd.OutOrStdout(), id)
			return nil
		},
	}
	return cmd
}
