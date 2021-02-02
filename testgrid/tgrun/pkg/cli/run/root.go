package run

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func RootCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use: "tgrun",
		PreRun: func(cmd *cobra.Command, args []string) {
			viper.BindPFlags(cmd.PersistentFlags())
			viper.BindPFlags(cmd.Flags())
		},
		Run: func(cmd *cobra.Command, args []string) {
			cmd.Help()
			os.Exit(1)
		},
	}

	cmd.PersistentFlags().String("api-endpoint", "https://api.testgrid.kurl.sh", "set to change the location of the testgrid api")
	cmd.PersistentFlags().String("api-token", "", "API token for authentication")

	cobra.OnInitialize(initConfig)

	cmd.AddCommand(QueueCmd())
	cmd.AddCommand(RunCmd())
	cmd.AddCommand(CleanCmd())

	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))
	return cmd
}

func InitAndExecute() {
	if err := RootCmd().Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func initConfig() {
	viper.SetEnvPrefix("TESTGRID")
	viper.AutomaticEnv()
}
