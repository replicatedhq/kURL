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

func NewClusterNodesMissingImageCmd(_ CLI) *cobra.Command {
	var opts cluster.NodeImagesJobOptions
	var excludeHostDeprecated string

	cmd := &cobra.Command{
		Use:   "nodes-missing-images IMAGE [IMAGE...]",
		Short: "Lists nodes missing the provided image(s). If a node is missing multiple images, it is only returned once.",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			logger := log.New(os.Stderr, "", 0)

			if excludeHostDeprecated != "" {
				opts.ExcludeNodes = append(opts.ExcludeNodes, excludeHostDeprecated)
			}

			nodesMissingImages, err := cluster.NodesMissingImages(cmd.Context(), clientSet, logger, args, opts)
			if err != nil {
				return fmt.Errorf("failed to determine what nodes were missing images: %w", err)
			}

			fmt.Fprintf(cmd.OutOrStdout(), "%s\n", strings.Join(nodesMissingImages, " "))
			return nil
		},
		SilenceUsage: true,
	}

	cmd.Flags().StringVar(&opts.TargetNode, "target-host", "", "a hostname that will be targeted in the search")
	cmd.Flags().StringSliceVar(&opts.ExcludeNodes, "exclude-host", nil, "a hostname or list of hostnames that will be excluded from the output")
	cmd.Flags().StringVar(&excludeHostDeprecated, "exclude_host", "", "a hostname that will be excluded from the output")
	_ = cmd.Flags().MarkDeprecated("exclude_host", "use --exclude-host instead")
	cmd.Flags().StringVar(&opts.JobImage, "image", cluster.DefaultNodeImagesJobImage, "the image to use to list images - must have 'docker' CLI on the path")
	cmd.Flags().StringVar(&opts.JobNamespace, "namespace", cluster.DefaultNodeImagesJobNamespace, "the namespace in which to run the discovery job")
	cmd.Flags().DurationVar(&opts.Timeout, "timeout", cluster.DefaultNodeImagesJobTimeout, "the timeout for the discovery job")

	return cmd
}

func NewClusterNodeListMissingImageCmd(_ CLI) *cobra.Command {
	var targetNode string
	var opts cluster.NodeImagesJobOptions
	var excludeHostDeprecated string

	cmd := &cobra.Command{
		Use:   "node-list-missing-images IMAGE [IMAGE...]",
		Short: "Lists missing images from the provided image(s) for a given node.",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			k8sConfig := config.GetConfigOrDie()
			clientSet := kubernetes.NewForConfigOrDie(k8sConfig)

			logger := log.New(os.Stderr, "", 0)

			if excludeHostDeprecated != "" {
				opts.ExcludeNodes = append(opts.ExcludeNodes, excludeHostDeprecated)
			}

			nodeMissingImages, err := cluster.NodeListMissingImages(cmd.Context(), clientSet, logger, targetNode, args, opts)
			if err != nil {
				return fmt.Errorf("failed to determine what images were missing from node %s images: %w", targetNode, err)
			}

			fmt.Fprintf(cmd.OutOrStdout(), "%s\n", strings.Join(nodeMissingImages, " "))
			return nil
		},
		SilenceUsage: true,
	}

	cmd.Flags().StringVar(&targetNode, "target-host", "", "a hostname that will be targeted in the search")
	cmd.MarkFlagRequired("target-host")
	cmd.Flags().StringVar(&opts.JobImage, "image", cluster.DefaultNodeImagesJobImage, "the image to use to list images - must have 'docker' CLI on the path")
	cmd.Flags().StringVar(&opts.JobNamespace, "namespace", cluster.DefaultNodeImagesJobNamespace, "the namespace in which to run the discovery job")
	cmd.Flags().DurationVar(&opts.Timeout, "timeout", cluster.DefaultNodeImagesJobTimeout, "the timeout for the discovery job")

	return cmd
}
