package cli

import (
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/replicatedhq/kurl/pkg/cluster"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func NewClusterNodesMissingImageCmd(cli CLI) *cobra.Command {
	var excludeHost, excludeHostDeprecated string
	var opts cluster.NodeImagesJobOptions

	cmd := &cobra.Command{
		Use:   "nodes-missing-images IMAGE...",
		Short: "Lists nodes missing the provided image(s). If a node is missing multiple images, it is only returned once.",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			logger := log.New(os.Stderr, "", 0)

			if excludeHost == "" {
				excludeHost = excludeHostDeprecated
			}

			nodesMissingImages, err := cluster.NodesMissingImages(cmd.Context(), clientSet, logger, args, opts)
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

	cmd.Flags().StringVar(&excludeHost, "exclude-host", "", "A hostname that will be excluded from the output")
	cmd.Flags().StringVar(&excludeHostDeprecated, "exclude_host", "", "A hostname that will be excluded from the output")
	_ = cmd.Flags().MarkDeprecated("exclude_host", "use --exclude-host instead")
	cmd.Flags().StringVar(&opts.JobImage, "image", cluster.DefaultNodeImagesJobImage, "the image to use to list images - must have 'docker' CLI on the path")
	cmd.Flags().StringVar(&opts.JobNamespace, "namespace", cluster.DefaultNodeImagesJobNamespace, "the namespace in which to run the discovery job")
	cmd.Flags().DurationVar(&opts.Timeout, "timeout", cluster.DefaultNodeImagesJobTimeout, "the timeout for the discovery job")

	return cmd
}
