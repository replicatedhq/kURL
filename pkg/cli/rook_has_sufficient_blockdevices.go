package cli

import (
	"fmt"

	"github.com/replicatedhq/kurl/pkg/rook"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewRookHasSufficientBlockDevicesCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "has-sufficient-blockdevices",
		Short: "Returns the 0 if there are enough block devices in the cluster, 1 otherwise",
		RunE: func(cmd *cobra.Command, args []string) error {

			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			rook.InitWriter(cmd.OutOrStdout())

			enoughOSDs, err := rook.HasSufficientBlockOSDs(cmd.Context(), clientSet)
			if err != nil {
				return fmt.Errorf("failed to check OSDs: %w", err)
			}

			if enoughOSDs {
				return nil
			}

			return fmt.Errorf("insufficient block device OSDs")
		},
		SilenceUsage: true,
	}
	return cmd
}
