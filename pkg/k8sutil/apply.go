package k8sutil

import (
	"bytes"
	"context"
	"os/exec"
)

func KubectlApply(ctx context.Context, b []byte, args ...string) ([]byte, error) {
	args = append([]string{"apply", "-f", "-"}, args...)
	cmd := exec.CommandContext(ctx, "kubectl", args...)
	cmd.Stdin = bytes.NewReader(b)
	return cmd.CombinedOutput()
}
