package cli

import (
	"fmt"

	"github.com/replicatedhq/kurl/pkg/rook"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewRookWaitForHealthCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "wait-for-health",
		Short: "Waits for Rook to report that it is healthy, and prints what it's waiting for",
		RunE: func(cmd *cobra.Command, args []string) error {
			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			rook.InitWriter(cmd.OutOrStdout())

			err := rook.WaitForRookHealth(cmd.Context(), clientSet)
			if err != nil {
				return fmt.Errorf("failed to check rook health: %w", err)
			}

			fmt.Printf("Rook is healthy")
			return nil
		},
		SilenceUsage: true,
	}
	return cmd
}
