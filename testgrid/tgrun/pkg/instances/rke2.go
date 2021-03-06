package instances

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

func init() {
	RegisterAirgapAndOnlineInstance(
		types.Instance{
			InstallerSpec: types.InstallerSpec{
				RKE2: &kurlv1beta1.RKE2{
					Version: "latest",
				},
				Rook: &kurlv1beta1.Rook{
					Version:                    "1.4.3",
					HostpathRequiresPrivileged: true,
					StorageClassName:           "default",
					IsBlockStorageEnabled:      true,
				},
				Registry: &kurlv1beta1.Registry{
					Version: "latest",
				},
				Velero: &kurlv1beta1.Velero{
					Version:                  "latest",
					ResticRequiresPrivileged: true,
				},
				Kotsadm: &kurlv1beta1.Kotsadm{
					Version:    "latest",
					UiBindPort: 30880,
				},
			},
			UnsupportedOSIDs: []string{
				"ubuntu-1604",
				"ubuntu-1804",
				"ubuntu-2004",
			},
		},
	)
}
