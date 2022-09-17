package cli

import (
	"context"
	"fmt"
	"time"

	"github.com/replicatedhq/kurl/pkg/rook"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewRookWaitForRookVersionCmd(cli CLI) *cobra.Command {
	timeoutSeconds := 0
	cmd := &cobra.Command{
		Use:   "wait-for-rook-version VERSION",
		Short: "Waits for all deployments to be using the specified rook version, and prints deployments that are still on an old version",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			rookVersion := args[0]

			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			ctx := cmd.Context()
			if timeoutSeconds != 0 {
				newCtx, cancel := context.WithTimeout(ctx, time.Duration(timeoutSeconds)*time.Second)
				defer cancel()
				ctx = newCtx
			}

			rook.InitWriter(cmd.OutOrStdout())

			err := rook.WaitForRookOrCephVersion(ctx, clientSet, rookVersion, "rook-version", "Rook")
			if err != nil {
				return fmt.Errorf("failed to wait for Rook %q: %w", rookVersion, err)
			}

			fmt.Fprintf(cmd.OutOrStdout(), "\nRook %q has been rolled out\n", rookVersion)
			return nil
		},
		SilenceUsage: true,
	}
	cmd.Flags().IntVar(&timeoutSeconds, "timeout", 0, "the maximum time to wait for the rook version to be deployed")
	return cmd
}

func NewRookWaitForCephVersionCmd(cli CLI) *cobra.Command {
	timeoutSeconds := 0
	cmd := &cobra.Command{
		Use:   "wait-for-ceph-version VERSION",
		Short: "Waits for all deployments to be using the specified ceph version, and prints deployments that are still on an old version",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			rookVersion := args[0]

			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			ctx := cmd.Context()
			if timeoutSeconds != 0 {
				newCtx, cancel := context.WithTimeout(ctx, time.Duration(timeoutSeconds)*time.Second)
				defer cancel()
				ctx = newCtx
			}

			rook.InitWriter(cmd.OutOrStdout())

			err := rook.WaitForRookOrCephVersion(ctx, clientSet, rookVersion, "ceph-version", "Ceph")
			if err != nil {
				return fmt.Errorf("failed to wait for Ceph %q: %w", rookVersion, err)
			}

			fmt.Fprintf(cmd.OutOrStdout(), "\nCeph %q has been rolled out\n", rookVersion)
			return nil
		},
		SilenceUsage: true,
	}
	cmd.Flags().IntVar(&timeoutSeconds, "timeout", 0, "the maximum time to wait for the rook version to be deployed")
	return cmd
}
