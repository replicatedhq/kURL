package cli

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
)

func newFormatAddressCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "format-address",
		Short: "Adds brackets around ipv6 addresses",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			address := formatAddress(args[0])

			_, err := fmt.Fprintln(cmd.OutOrStdout(), address)

			return err
		},
	}
	return cmd
}

func formatAddress(addr string) string {
	if strings.Contains(addr, ":") {
		return fmt.Sprintf("[%s]", addr)
	}

	return addr
}
