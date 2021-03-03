package cli

import (
	"fmt"

	"github.com/replicatedhq/kurl/pkg/machineid"
	"github.com/spf13/cobra"
)

func NewMachineidCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "machineid",
		Short: "Prints the kURL machine id",
		RunE: func(cmd *cobra.Command, args []string) error {
			id, err := machineid.ID()
			if err != nil {
				return err
			}
			fmt.Fprintln(cmd.OutOrStdout(), id)
			return nil
		},
	}
	return cmd
}
