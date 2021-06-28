package instances

import (
	"path/filepath"
	"runtime"
	"strings"

	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

var Instances = []types.Instance{}

func RegisterInstance(instance types.Instance) {
	_, file, _, _ := runtime.Caller(1)
	name := strings.Split(filepath.Base(file), ".")[0]

	instance.Name = name
	Instances = append(Instances, instance)
}

func RegisterAirgapAndOnlineInstance(instance types.Instance) {
	_, file, _, _ := runtime.Caller(1)
	name := strings.Split(filepath.Base(file), ".")[0]

	instance.Name = name
	Instances = append(Instances, instance)

	duplicate := instance
	duplicate.Name = name + "-airgap"
	duplicate.Airgap = true
	Instances = append(Instances, duplicate)
}
