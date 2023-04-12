package k8sutil

import (
	"bytes"
	"context"
	"embed"
	"os/exec"

	"github.com/replicatedhq/plumber/v2"
	"sigs.k8s.io/controller-runtime/pkg/client"
	kustomizetypes "sigs.k8s.io/kustomize/api/types"
)

func KubectlApply(ctx context.Context, cli client.Client, resources embed.FS, overlay string, opts ...plumber.Option) error {
	options := append([]plumber.Option{
		plumber.WithKustomizeMutator(
			func(ctx context.Context, k *kustomizetypes.Kustomization) error {
				k.CommonLabels = AppendKurlLabels(k.CommonLabels)
				return nil
			},
		),
	}, opts...)

	err := plumber.NewRenderer(cli, resources, options...).Apply(
		ctx, overlay,
	)
	return err
}

func KubectlDelete(ctx context.Context, b []byte, args ...string) ([]byte, error) {
	args = append([]string{"delete", "-f", "-"}, args...)
	cmd := exec.CommandContext(ctx, "kubectl", args...)
	cmd.Stdin = bytes.NewReader(b)
	return cmd.CombinedOutput()
}
