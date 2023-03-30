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
	hostCmd.AddCommand(newHostnameCmd(cli))
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
	clusterCmd.AddCommand(newPreflightCmd(cli))
	cmd.AddCommand(clusterCmd)

	netutilCmd := newNetutilCommand(cli)
	netutilCmd.AddCommand(newNetutilIfaceFromIPCommand(cli))
	netutilCmd.AddCommand(newNetutilDefaultIfaceCommand(cli))
	netutilCmd.AddCommand(newNetutilFormatIPAddressCmd(cli))
	cmd.AddCommand(netutilCmd)

	objectStoreCmd := newObjectStoreCmd(cli)
	objectStoreCmd.AddCommand(newSyncObjectStoreCmd(cli))
	cmd.AddCommand(objectStoreCmd)

	cmd.AddCommand(newSyncObjectStoreCmdDeprecated(cli))
	cmd.AddCommand(newNetutilFormatIPAddressCmdDeprecated(cli))
}
