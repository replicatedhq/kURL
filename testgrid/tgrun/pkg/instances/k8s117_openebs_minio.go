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
					Version: "1.17.13",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "2.5.2",
				},
				Contour: &kurlv1beta1.Contour{
					Version: "1.0.1",
				},
				Docker: &kurlv1beta1.Docker{
					Version: "19.03.10",
				},
				Prometheus: &kurlv1beta1.Prometheus{
					Version: "0.33.0",
				},
				Registry: &kurlv1beta1.Registry{
					Version: "2.7.1",
				},
				Velero: &kurlv1beta1.Velero{
					Version: "1.2.0",
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version: "1.29.1",
				},
				OpenEBS: &kurlv1beta1.OpenEBS{
					Version:                 "1.12.0",
					Namespace:               "openebs",
					IsLocalPVEnabled:        true,
					LocalPVStorageClassName: "openebs",
					IsCstorEnabled:          true,
					CstorStorageClassName:   "default",
				},
				Ekco: &kurlv1beta1.Ekco{
					Version: "0.6.0",
				},
				Minio: &kurlv1beta1.Minio{
					Version:   "latest",
					Namespace: "minio",
				},
			},
		},
	)
}
