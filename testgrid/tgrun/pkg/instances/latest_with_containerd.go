package instances

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

func init() {
	Instances = append(
		Instances,
		types.InstallerSpec{
			Kubernetes: kurlv1beta1.Kubernetes{
				Version: "latest",
			},
			Weave: &kurlv1beta1.Weave{
				Version: "latest",
			},
			Rook: &kurlv1beta1.Rook{
				Version: "latest",
			},
			Contour: &kurlv1beta1.Contour{
				Version: "latest",
			},
			Containerd: &kurlv1beta1.Containerd{
				Version: "latest",
			},
			Prometheus: &kurlv1beta1.Prometheus{
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
	)
}
