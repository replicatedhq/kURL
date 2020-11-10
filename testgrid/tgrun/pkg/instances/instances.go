package instances

import "github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"

var Instances = []types.Instance{}

func RegisterInstance(instance types.Instance) {
	if instance.InstallerSpec.Docker == nil || instance.InstallerSpec.Docker.Version != "19.03.4" {
		return
	}
	Instances = append(Instances, instance)
}
