package preflight

import (
	"context"

	"github.com/pkg/errors"
	analyze "github.com/replicatedhq/troubleshoot/pkg/analyze"
	troubleshootv1beta2 "github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
)

var _ RunnerHost = new(RunnerHostPreflight)
var _ RunnerCluster = new(RunnerClusterPreflight)

type RunnerHost interface {
	RunHostPreflights(ctx context.Context, spec *troubleshootv1beta2.HostPreflight, progressChan chan interface{}) ([]*analyze.AnalyzeResult, error)
}

type RunnerCluster interface {
	RunClusterPreflight(spec *troubleshootv1beta2.Preflight, progressChan chan interface{}) ([]*analyze.AnalyzeResult, error)
}

type RunnerHostPreflight struct {
}

type RunnerClusterPreflight struct {
}

func (r *RunnerHostPreflight) RunHostPreflights(ctx context.Context, spec *troubleshootv1beta2.HostPreflight, progressChan chan interface{}) ([]*analyze.AnalyzeResult, error) {
	collectResults, err := CollectHostResults(ctx, spec, progressChan)
	if err != nil {
		return nil, errors.Wrap(err, "collect results")
	}
	return collectResults.Analyze(), nil
}

func (r *RunnerClusterPreflight) RunClusterPreflight(spec *troubleshootv1beta2.Preflight, progressChan chan interface{}) ([]*analyze.AnalyzeResult, error) {
	collectResults, err := CollectResults(spec, progressChan)
	if err != nil {
		return nil, errors.Wrap(err, "collect results")
	}
	return collectResults.Analyze(), nil
}
