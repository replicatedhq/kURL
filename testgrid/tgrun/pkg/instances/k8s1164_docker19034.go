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
					Version: "1.16.4",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "2.6.5",
				},
				Rook: &kurlv1beta1.Rook{
					Version:               "1.4.3",
					IsBlockStorageEnabled: true,
				},
				Ekco: &kurlv1beta1.Ekco{
					Version: "0.7.0",
				},
				Contour: &kurlv1beta1.Contour{
					Version: "1.7.0",
				},
				Docker: &kurlv1beta1.Docker{
					Version: "19.03.4",
				},
				Registry: &kurlv1beta1.Registry{
					Version: "2.7.1",
				},
				Velero: &kurlv1beta1.Velero{
					Version: "1.5.1",
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version: "1.24.1",
				},
			},
			UnsupportedOSIDs: []string{
				"ubuntu-2004",
			},
		},
	)
}
