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
					Version: "1.19.7",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "2.7.0",
				},
				Containerd: &kurlv1beta1.Containerd{
					Version: "1.4.3",
				},
				Longhorn: &kurlv1beta1.Longhorn{
					Version:    "1.1.0",
					UiBindPort: 30080,
				},
				Contour: &kurlv1beta1.Contour{
					Version: "1.7.0",
				},
				Registry: &kurlv1beta1.Registry{
					Version: "2.7.1",
				},
				Ekco: &kurlv1beta1.Ekco{
					Version: "0.7.0",
				},
				Fluentd: &kurlv1beta1.Fluentd{
					FullEFKStack: true,
					Version:      "1.7.4",
				},
				CertManager: &kurlv1beta1.CertManager{
					Version: "1.0.3",
				},
				Minio: &kurlv1beta1.Minio{
					Version: "latest",
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version:    "1.25.2",
					UiBindPort: 30880,
				},
			},
		},
	)
}
