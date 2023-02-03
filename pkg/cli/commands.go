package cli

import (
	"github.com/spf13/cobra"
)

// AddCommands adds version/host/objectstore/newformataddress commands to the cobra object
func AddCommands(cmd *cobra.Command, cli CLI) {
	cmd.AddCommand(newVersionCmd(cli))

	hostCmd := newHostCmd(cli)
	hostCmd.AddCommand(newHostProtectedidCmd(cli))
	hostCmd.AddCommand(newHostPreflightCmd(cli))
	cmd.AddCommand(hostCmd)

	rookCmd := NewRookCmd(cli)
	rookCmd.AddCommand(NewHostpathToBlockCmd(cli))
	rookCmd.AddCommand(NewRookHealthCmd(cli))
	rookCmd.AddCommand(NewRookWaitForHealthCmd(cli))
	rookCmd.AddCommand(NewRookWaitForRookVersionCmd(cli))
	rookCmd.AddCommand(NewRookWaitForCephVersionCmd(cli))
	rookCmd.AddCommand(NewRookHasSufficientBlockDevicesCmd(cli))
	rookCmd.AddCommand(NewRookFlexvolumeToCSI(cli))
	cmd.AddCommand(rookCmd)

	longhornCmd := NewLonghornCmd(cli)
	longhornCmd.AddCommand(NewLonghornPrepareForMigration(cli))
	longhornCmd.AddCommand(NewLonghornRollbackMigrationReplicas(cli))
	cmd.AddCommand(longhornCmd)

	clusterCmd := NewClusterCmd(cli)
	clusterCmd.AddCommand(NewClusterNodesMissingImageCmd(cli))
	clusterCmd.AddCommand(NewClusterCheckFreeDiskSpaceCmd(cli))
	cmd.AddCommand(clusterCmd)

	utilCmd := newUtilCommand(cli)
	utilCmd.AddCommand(newUtilIfaceFromIPCommand(cli))
	utilCmd.AddCommand(newUtilDefaultIfaceCommand(cli))
	cmd.AddCommand(utilCmd)

	cmd.AddCommand(newSyncObjectStoreCmd(cli))

	cmd.AddCommand(newFormatAddressCmd(cli))
}
