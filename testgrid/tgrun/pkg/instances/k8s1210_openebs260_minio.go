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
					Version: "1.20.5",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "2.8.1",
				},
				Docker: &kurlv1beta1.Docker{
					Version: "20.10.5",
				},
				Registry: &kurlv1beta1.Registry{
					Version: "2.7.1",
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version: "latest",
				},
				OpenEBS: &kurlv1beta1.OpenEBS{
					Version:                 "2.6.0",
					Namespace:               "openebs",
					IsLocalPVEnabled:        true,
					LocalPVStorageClassName: "openebs",
					IsCstorEnabled:          true,
					CstorStorageClassName:   "default",
				},
				Ekco: &kurlv1beta1.Ekco{
					Version: "0.10.1",
				},
				Minio: &kurlv1beta1.Minio{
					Version:   "latest",
					Namespace: "minio",
				},
			},
		},
	)
}
