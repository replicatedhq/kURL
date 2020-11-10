package instances

import "github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"

var Instances = []types.Instance{}

func RegisterInstance(instance types.Instance) {
	Instances = append(Instances, instance)
}
