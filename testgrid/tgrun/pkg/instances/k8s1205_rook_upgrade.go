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
				Containerd: &kurlv1beta1.Containerd{
					Version: "1.4.4",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "2.8.1",
				},
				Rook: &kurlv1beta1.Rook{
					Version:               "1.4.3",
					IsBlockStorageEnabled: true,
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version: "1.38.0",
				},
			},
			UpgradeSpec: &types.InstallerSpec{
				Kubernetes: &kurlv1beta1.Kubernetes{
					Version: "1.20.2",
				},
				Containerd: &kurlv1beta1.Containerd{
					Version: "1.4.4",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "2.8.1",
				},
				Rook: &kurlv1beta1.Rook{
					Version:               "1.5.9",
					IsBlockStorageEnabled: true,
					BypassUpgradeWarning:  true,
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version: "1.38.0",
				},
			},
		},
	)
}
