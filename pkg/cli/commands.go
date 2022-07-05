package cli

import "github.com/spf13/cobra"

// AddCommands adds version/host/objectstore/newformataddress commands to the cobra object
func AddCommands(cmd *cobra.Command, cli CLI) {
	cmd.AddCommand(newVersionCmd(cli))

	hostCmd := newHostCmd(cli)
	hostCmd.AddCommand(newHostProtectedidCmd(cli))
	hostCmd.AddCommand(newHostPreflightCmd(cli))
	cmd.AddCommand(hostCmd)

	cmd.AddCommand(newSyncObjectStoreCmd(cli))

	cmd.AddCommand(newFormatAddressCmd(cli))
}
