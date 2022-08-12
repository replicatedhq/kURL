package cli

import (
	"context"
	"fmt"
	"github.com/replicatedhq/kurl/pkg/rook"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
	"os"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewRookHealthCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "health",
		Short: "Checks rook-ceph health and returns any issues",
		RunE: func(cmd *cobra.Command, args []string) error {
			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			rook.InitWriter(os.Stdout)

			healthy, errMsg, err := rook.RookHealth(context.TODO(), clientSet)
			if err != nil {
				fmt.Printf("failed to check rook health: %s", err.Error())
				return nil
			}
			if !healthy {
				fmt.Printf("rook unhealthy: %s", errMsg)
				return nil
			}

			return nil
		},
	}
	return cmd
}
