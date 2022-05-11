package run

import (
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler"
	schedulertypes "github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func QueueCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:           "queue",
		SilenceUsage:  true,
		SilenceErrors: false,
		PreRun: func(cmd *cobra.Command, args []string) {
			viper.BindPFlags(cmd.PersistentFlags())
			viper.BindPFlags(cmd.Flags())
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			v := viper.GetViper()

			schedulerOptions := schedulertypes.SchedulerOptions{
				APIEndpoint:  v.GetString("api-endpoint"),
				APIToken:     v.GetString("api-token"),
				OverwriteRef: v.GetBool("overwrite-ref"),
				Ref:          v.GetString("ref"),
				Staging:      v.GetBool("staging"),
				Airgap:       v.GetBool("airgap"),
				KurlVersion:  v.GetString("kurl-version"),
				Spec:         v.GetString("spec"),
				OSSpec:       v.GetString("os-spec"),
			}

			if err := scheduler.Run(schedulerOptions); err != nil {
				return err
			}

			return nil
		},
	}

	cmd.Flags().String("ref", "", "ref to report to testgrid")
	cmd.MarkFlagRequired("ref")
	cmd.Flags().Bool("overwrite-ref", false, "when set, overwrite the ref on the testgrid")
	cmd.Flags().Bool("staging", false, "when set, run tests against staging.kurl.sh instead of kurl.sh")
	cmd.Flags().Bool("airgap", false, "when set, run tests in airgapped mode")
	cmd.Flags().Bool("latest-only", false, "when set, run tests against the 'latest' kurl installer only instead of the standard suite")
	cmd.Flags().String("kurl-version", "", "when set, run a specific kurl version")
	cmd.Flags().String("spec", "", "run test against the provided installer spec yaml")
	cmd.MarkFlagRequired("spec")
	cmd.Flags().String("os-spec", "", "run test against the provided os spec yaml")
	cmd.MarkFlagRequired("os-spec")
	cmd.MarkFlagRequired("ref")

	return cmd
}
