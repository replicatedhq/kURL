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
					Version: "1.20.4",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "2.7.0",
				},
				Longhorn: &kurlv1beta1.Longhorn{
					Version: "1.1.0",
				},
				Ekco: &kurlv1beta1.Ekco{
					Version: "latest",
				},
				Contour: &kurlv1beta1.Contour{
					Version: "1.13.1",
				},
				Containerd: &kurlv1beta1.Containerd{
					Version: "1.4.4",
				},
				Prometheus: &kurlv1beta1.Prometheus{
					Version: "0.44.1",
				},
				Registry: &kurlv1beta1.Registry{
					Version: "2.7.1",
				},
				Velero: &kurlv1beta1.Velero{
					Version: "1.5.3",
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version: "latest",
				},
			},
		},
	)
}
