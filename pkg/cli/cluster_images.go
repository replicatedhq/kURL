package cli

import (
	"fmt"
	"strings"

	"github.com/replicatedhq/kurl/pkg/cluster"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewClusterNodesMissingImageCmd(cli CLI) *cobra.Command {
	var excludeHost string

	cmd := &cobra.Command{
		Use:   "nodes-missing-images IMAGE...",
		Short: "Lists nodes missing the provided image(s). If a node is missing multiple images, it is only returned once.",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			nodesMissingImages, err := cluster.NodesMissingImages(cmd.Context(), clientSet, args)
			if err != nil {
				return fmt.Errorf("failed to determine what nodes were missing images: %w", err)
			}

			if excludeHost != "" {
				for idx, item := range nodesMissingImages {
					if item == excludeHost {
						// exclude this index from nodesMissingImages
						nodesMissingImages = append(nodesMissingImages[:idx], nodesMissingImages[idx+1:]...)
						break
					}
				}
			}

			fmt.Fprintf(cmd.OutOrStdout(), "%s\n", strings.Join(nodesMissingImages, " "))
			return nil
		},
		SilenceUsage: true,
	}

	cmd.Flags().StringVar(&excludeHost, "exclude_host", "", "A hostname that will be excluded from the output")

	return cmd
}
