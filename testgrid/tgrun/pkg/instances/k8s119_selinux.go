package instances

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

func init() {
	RegisterInstance(types.Instance{
		InstallerSpec: types.InstallerSpec{
			Kubernetes: &kurlv1beta1.Kubernetes{
				Version: "1.19.3",
			},
			Weave: &kurlv1beta1.Weave{
				Version: "2.8.1",
			},
			Docker: &kurlv1beta1.Docker{
				Version: "19.03.15",
			},
			SelinuxConfig: &kurlv1beta1.SelinuxConfig{
				Selinux: "permissive",
				Type:    "targeted",
				SemanageCmds: [][]string{{
					"user",
					"-a",
					"-R",
					"staff_r sysadm_r system_r",
					"-r",
					"s0-s0:c0.c1023",
					"my_staff_u",
				}},
				DisableSelinux: false,
				PreserveConfig: false,
			},
		},
	})
}
