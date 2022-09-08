package cli

import "github.com/spf13/cobra"

func AddCommands(cmd *cobra.Command, cli CLI) {
	cmd.AddCommand(NewVersionCmd(cli))

	hostCmd := NewHostCmd(cli)
	hostCmd.AddCommand(NewHostProtectedidCmd(cli))
	hostCmd.AddCommand(NewHostPreflightCmd(cli))
	cmd.AddCommand(hostCmd)

	rookCmd := NewRookCmd(cli)
	rookCmd.AddCommand(NewHostpathToBlockCmd(cli))
	rookCmd.AddCommand(NewRookHealthCmd(cli))
	rookCmd.AddCommand(NewRookWaitForHealthCmd(cli))
	rookCmd.AddCommand(NewRookWaitForRookVersionCmd(cli))
	rookCmd.AddCommand(NewRookWaitForCephVersionCmd(cli))
	rookCmd.AddCommand(NewRookHasSufficientBlockDevicesCmd(cli))
	cmd.AddCommand(rookCmd)

	clusterCmd := NewClusterCmd(cli)
	clusterCmd.AddCommand(NewClusterNodesMissingImageCmd(cli))
	cmd.AddCommand(clusterCmd)

	cmd.AddCommand(NewSyncObjectStoreCmd(cli))

	cmd.AddCommand(NewFormatAddressCmd(cli))
}
