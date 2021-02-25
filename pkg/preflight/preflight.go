package preflight

import (
	"context"

	"github.com/pkg/errors"
	analyze "github.com/replicatedhq/troubleshoot/pkg/analyze"
	troubleshootv1beta2 "github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
	troubleshootclientsetscheme "github.com/replicatedhq/troubleshoot/pkg/client/troubleshootclientset/scheme"
	"github.com/replicatedhq/troubleshoot/pkg/preflight"
	"k8s.io/client-go/kubernetes/scheme"
)

func init() {
	troubleshootclientsetscheme.AddToScheme(scheme.Scheme)
}

func Run(ctx context.Context, data []byte) ([]*analyze.AnalyzeResult, error) {
	decode := scheme.Codecs.UniversalDeserializer().Decode
	obj, gvk, err := decode(data, nil, nil)
	if err != nil {
		return nil, errors.Wrap(err, "decode spec")
	}

	if gvk.Group != "troubleshoot.sh" || gvk.Version != "v1beta2" || gvk.Kind != "HostPreflight" {
		return nil, errors.Errorf("unexpected gvk %s", gvk)
	}

	spec, ok := obj.(*troubleshootv1beta2.HostPreflight)
	if !ok {
		return nil, errors.Errorf("unexpected type %T", obj)
	}

	ch := make(chan interface{})
	defer close(ch)
	go discardProgress(ch)

	collectOpts := preflight.CollectOpts{
		ProgressChan: ch,
	}
	collectResults, err := preflight.CollectHost(collectOpts, spec)
	if err != nil {
		return nil, errors.Wrap(err, "collect host")
	} else if collectResults == nil {
		return nil, errors.New("no results")
	}

	return collectResults.Analyze(), nil
}

func discardProgress(ch <-chan interface{}) {
	for range ch {
	}
}
