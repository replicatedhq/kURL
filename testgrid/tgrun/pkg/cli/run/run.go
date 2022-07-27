package run

import (
	"fmt"

	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner"
	runnertypes "github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/types"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/version"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func RunCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:           "run",
		SilenceUsage:  true,
		SilenceErrors: false,
		PreRun: func(cmd *cobra.Command, args []string) {
			viper.BindPFlags(cmd.PersistentFlags())
			viper.BindPFlags(cmd.Flags())
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			v := viper.GetViper()

			runnerOptions := runnertypes.RunnerOptions{
				APIEndpoint: v.GetString("api-endpoint"),
				APIToken:    v.GetString("api-token"),
			}

			fmt.Printf("starting tgrun:\n")
			version.Print()

			if err := runner.MainRunLoop(runnerOptions); err != nil {
				return err
			}

			return nil
		},
	}

	return cmd
}
