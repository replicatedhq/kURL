package instances

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

func init() {
	RegisterAirgapAndOnlineInstance(
		types.Instance{
			InstallerSpec: types.InstallerSpec{
				Kubernetes: &kurlv1beta1.Kubernetes{
					Version: "1.21.0",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "latest",
				},
				Rook: &kurlv1beta1.Rook{
					Version:               "1.4.9",
					IsBlockStorageEnabled: true,
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
				Registry: &kurlv1beta1.Registry{
					Version: "latest",
				},
				Velero: &kurlv1beta1.Velero{
					Version: "latest",
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version: "latest",
				},
			},
		},
	)
}
