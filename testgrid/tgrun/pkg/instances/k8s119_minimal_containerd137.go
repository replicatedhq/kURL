package instances

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

func init() {
	RegisterInstance(
		types.Instance{
			InstallerSpec: types.InstallerSpec{
				Kubernetes: kurlv1beta1.Kubernetes{
					Version: "1.19.7",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "2.6.4",
				},
				Contour: &kurlv1beta1.Contour{
					Version:   "1.11.0",
					HTTPPort:  8080,
					HTTPSPort: 8443,
				},
				Containerd: &kurlv1beta1.Containerd{
					Version: "1.3.7",
				},
			},
		},
	)
}
