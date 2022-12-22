package preflight

import (
	"context"

	"github.com/pkg/errors"
	analyze "github.com/replicatedhq/troubleshoot/pkg/analyze"
	troubleshootv1beta2 "github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
	troubleshootclientsetscheme "github.com/replicatedhq/troubleshoot/pkg/client/troubleshootclientset/scheme"
	"github.com/replicatedhq/troubleshoot/pkg/preflight"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/kubernetes/scheme"
)

func init() {
	utilruntime.Must(troubleshootclientsetscheme.AddToScheme(scheme.Scheme))
}

// Decode decodes preflight spec yaml files
func Decode(data []byte) (*troubleshootv1beta2.HostPreflight, error) {
	decode := scheme.Codecs.UniversalDeserializer().Decode
	obj, gvk, err := decode(data, nil, nil)
	if err != nil {
		return nil, errors.Wrap(err, "decode")
	}

	if gvk.Group != "troubleshoot.sh" || gvk.Version != "v1beta2" || gvk.Kind != "HostPreflight" {
		return nil, errors.Errorf("unexpected gvk %q", gvk)
	}

	spec, ok := obj.(*troubleshootv1beta2.HostPreflight)
	if !ok {
		return nil, errors.Errorf("unexpected type %T", obj)
	}
	return spec, nil
}

// Run collects host preflights and analyzes them, returning the analysis
func Run(ctx context.Context, spec *troubleshootv1beta2.HostPreflight, progressChan chan interface{}) ([]*analyze.AnalyzeResult, error) {
	collectResults, err := CollectResults(ctx, spec, progressChan)
	if err != nil {
		return nil, errors.Wrap(err, "collect results")
	}
	return collectResults.Analyze(), nil
}

// CollectResults collects host preflights, and returns the CollectResult
func CollectResults(_ context.Context, spec *troubleshootv1beta2.HostPreflight, progressChan chan interface{}) (preflight.CollectResult, error) {
	collectOpts := preflight.CollectOpts{
		ProgressChan: progressChan,
	}
	collectResults, err := preflight.CollectHost(collectOpts, spec)
	if err != nil {
		return nil, errors.Wrap(err, "collect host")
	} else if collectResults == nil {
		return nil, errors.New("no results")
	}

	return collectResults, nil
}
