package instances

import "github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"

var Instances = []types.Instance{}

func RegisterInstance(instance types.Instance) {
	Instances = append(Instances, instance)
}

func RegisterAirgapAndOnlineInstance(instance types.Instance) {
	Instances = append(Instances, instance)

	duplicate := instance
	if instance.UpgradeSpec != nil {
		duplicateUpgrade := *instance.UpgradeSpec
		duplicate.UpgradeSpec = &duplicateUpgrade
		duplicate.UpgradeSpec.RunAirgap = true
	}

	duplicate.InstallerSpec.RunAirgap = true
	Instances = append(Instances, duplicate)
}
