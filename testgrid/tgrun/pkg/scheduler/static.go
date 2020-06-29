package scheduler

import (
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

var operatingSystems = []types.OperatingSystemImage{
	{
		VMImageURI: "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2",
		Name:       "CentOS",
		Version:    "7",
		PVCPrefix:  "centos-7-",
	},
	{
		VMImageURI: "https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img",
		Name:       "Ubuntu",
		Version:    "18.04",
		PVCPrefix:  "ubuntu-18-",
	},
	// {
	// 	VMImageURI: "https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img",
	// 	Name:       "Ubuntu",
	// 	Version:    "16.04",
	// 	PVCPrefix:  "ubuntu-16-",
	// },
}
