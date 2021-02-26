package installer

import (
	"github.com/pkg/errors"
	kurlclientsetscheme "github.com/replicatedhq/kurl/kurlkinds/client/kurlclientset/scheme"
	clusterv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/spf13/afero"
	"k8s.io/client-go/kubernetes/scheme"
)

func init() {
	kurlclientsetscheme.AddToScheme(scheme.Scheme)
}

func RetrieveSpec(fs afero.Fs, filename string) (*clusterv1beta1.Installer, error) {
	data, err := afero.ReadFile(fs, filename)
	if err != nil {
		return nil, errors.Wrap(err, "read file")
	}

	decode := scheme.Codecs.UniversalDeserializer().Decode
	obj, gvk, err := decode(data, nil, nil)
	if err != nil {
		return nil, errors.Wrap(err, "decode spec")
	}

	if gvk.Group != "cluster.kurl.sh" || gvk.Version != "v1beta1" || gvk.Kind != "Installer" {
		return nil, errors.Errorf("unexpected gvk %q", gvk)
	}

	spec, ok := obj.(*clusterv1beta1.Installer)
	if !ok {
		return nil, errors.Errorf("unexpected type %T", obj)
	}
	return spec, nil
}
