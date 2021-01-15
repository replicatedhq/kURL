package instances

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

// Latest is the latest version(s) or the curl installer.
var Latest = []types.Instance{
	{
		InstallerSpec: types.InstallerSpec{
			Kubernetes: kurlv1beta1.Kubernetes{
				Version: "latest",
			},
			Weave: &kurlv1beta1.Weave{
				Version: "latest",
			},
			Rook: &kurlv1beta1.Rook{
				Version: "latest",
			},
			Ekco: &kurlv1beta1.Ekco{
				Version: "latest",
			},
			Contour: &kurlv1beta1.Contour{
				Version: "latest",
			},
			Docker: &kurlv1beta1.Docker{
				Version: "latest",
			},
			Prometheus: &kurlv1beta1.Prometheus{
				Version: "latest",
			},
			Registry: &kurlv1beta1.Registry{
				Version: "latest",
			},
		},
	},
}
