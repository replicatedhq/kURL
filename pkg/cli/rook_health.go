package cli

import (
	"fmt"

	"github.com/replicatedhq/kurl/pkg/rook"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewRookHealthCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "health",
		Short: "Checks rook-ceph health and returns any issues",
		RunE: func(cmd *cobra.Command, args []string) error {
			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			rook.InitWriter(cmd.OutOrStdout())

			healthy, errMsg, err := rook.RookHealth(cmd.Context(), clientSet)
			if err != nil {
				return fmt.Errorf("failed to check rook health: %w", err)
			}
			if !healthy {
				return fmt.Errorf("rook unhealthy: %s", errMsg)
			}

			fmt.Printf("Rook is healthy")
			return nil
		},
		SilenceUsage: true,
	}
	return cmd
}
