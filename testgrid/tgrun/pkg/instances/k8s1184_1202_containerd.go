package instances

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

func init() {
	RegisterInstance(
		types.Instance{
			InstallerSpec: types.InstallerSpec{
				Kubernetes: &kurlv1beta1.Kubernetes{
					Version: "1.18.4",
				},
				Antrea: &kurlv1beta1.Antrea{
					Version: "0.13.1",
				},
				Contour: &kurlv1beta1.Contour{
					Version: "1.0.1",
				},
				Containerd: &kurlv1beta1.Containerd{
					Version: "1.4.3",
				},
			},
			UpgradeSpec: &types.InstallerSpec{
				Kubernetes: &kurlv1beta1.Kubernetes{
					Version: "1.20.2",
				},
				Antrea: &kurlv1beta1.Antrea{
					Version: "0.13.1",
				},
				Contour: &kurlv1beta1.Contour{
					Version: "latest",
				},
				Containerd: &kurlv1beta1.Containerd{
					Version: "1.4.3",
				},
			},
		},
	)
}
