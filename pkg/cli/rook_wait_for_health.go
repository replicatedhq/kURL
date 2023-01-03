package cli

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/replicatedhq/kurl/pkg/rook"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewRookWaitForHealthCmd(_ CLI) *cobra.Command {
	var ignoreChecks []string
	cmd := &cobra.Command{
		Use:   "wait-for-health [TIMEOUT]",
		Short: "Waits for Rook to report that it is healthy, and prints what it's waiting for",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			rook.InitWriter(cmd.OutOrStdout())

			ctx := cmd.Context()

			if len(args) == 1 {
				// a timeout was provided, use it
				timeout, err := strconv.ParseInt(args[0], 10, 64)
				if err != nil {
					return fmt.Errorf("failed to parse %q as an integer number of seconds: %w", args[0], err)
				}
				var cancel context.CancelFunc
				ctx, cancel = context.WithTimeout(ctx, time.Second*time.Duration(timeout))
				defer cancel()
			}

			err := rook.WaitForRookHealth(ctx, clientSet, ignoreChecks)
			if err != nil {
				return fmt.Errorf("failed to check rook health: %w", err)
			}

			fmt.Fprintln(cmd.OutOrStdout(), "Rook is healthy")
			return nil
		},
		SilenceUsage: true,
	}
	cmd.Flags().StringSliceVar(&ignoreChecks, "ignore-checks", nil, "a list of Ceph health check unique identifiers to ignore when reporting health")
	return cmd
}
