package cli

import "github.com/spf13/cobra"

func AddCommands(cmd *cobra.Command, cli CLI) {
	cmd.AddCommand(NewVersionCmd(cli))
	cmd.AddCommand(NewMachineidCmd(cli))
	cmd.AddCommand(NewPreflightCmd(cli))
}
