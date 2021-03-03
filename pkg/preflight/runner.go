package preflight

import (
	"context"

	"github.com/pkg/errors"
	analyze "github.com/replicatedhq/troubleshoot/pkg/analyze"
	troubleshootv1beta2 "github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
)

var _ Runner = new(PreflightRunner)

type Runner interface {
	Run(ctx context.Context, spec *troubleshootv1beta2.HostPreflight, progressChan chan interface{}) ([]*analyze.AnalyzeResult, error)
}

type PreflightRunner struct {
}

func (r *PreflightRunner) Run(ctx context.Context, spec *troubleshootv1beta2.HostPreflight, progressChan chan interface{}) ([]*analyze.AnalyzeResult, error) {
	collectResults, err := CollectResults(ctx, spec, progressChan)
	if err != nil {
		return nil, errors.Wrap(err, "collect results")
	}
	return collectResults.Analyze(), nil
}
