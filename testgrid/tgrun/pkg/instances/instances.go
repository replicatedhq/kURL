package instances

import "github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"

var Instances = []types.InstallerSpec{}

func RegisterInstance(instance types.InstallerSpec) {
	Instances = append(Instances, instance)
}
