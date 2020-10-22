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
					Version: "1.19.3",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "2.6.4",
				},
				Docker: &kurlv1beta1.Docker{
					Version: "19.03.10",
				},
				Kurl: &kurlv1beta1.Kurl{
					Nameserver: "8.8.8.8",
				},
			},
		},
	)
}
