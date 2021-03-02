package instances

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

func init() {
	RegisterAirgapAndOnlineInstance(
		types.Instance{
			InstallerSpec: types.InstallerSpec{
				K3S: &kurlv1beta1.K3S{
					Version: "latest",
				},
				Prometheus: &kurlv1beta1.Prometheus{
					Version: "latest",
				},
				Registry: &kurlv1beta1.Registry{
					Version: "latest",
				},
				Minio: &kurlv1beta1.Minio{
					Version: "latest",
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version:    "latest",
					UiBindPort: 30880,
				},
			},
		},
	)
}
