package cli

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
)

func NewFormatAddressCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "format-address",
		Short: "Adds brackets around ipv6 addresses",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			address := args[0]

			if strings.Contains(address, ":") {
				address = fmt.Sprintf("[%s]", address)
			}

			_, err := fmt.Fprintln(cmd.OutOrStdout(), address)

			return err
		},
	}
	return cmd
}
