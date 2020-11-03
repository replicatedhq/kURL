package scheduler

import (
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

var operatingSystems = []types.OperatingSystemImage{
	{
		VMImageURI: "https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img",
		Name:       "Ubuntu",
		Version:    "18.04",
		PVCPrefix:  "ubuntu-18-",
	},
	{
		VMImageURI: "https://testgrid-images.s3.amazonaws.com/ubuntu/16.04/ubuntu-16.04-kernel-4.15.0-122-generic.qcow2",
		Name:       "Ubuntu",
		Version:    "16.04",
		PVCPrefix:  "ubuntu-16-",
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-2003.qcow2",
		Name:       "CentOS",
		Version:    "7.8",
		PVCPrefix:  "centos-78-",
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2",
		Name:       "CentOS",
		Version:    "8.2",
		PVCPrefix:  "centos-82-",
	},
	{
		VMImageURI: "https://cdn.amazonlinux.com/os-images/2.0.20200917.0/kvm/amzn2-kvm-2.0.20200917.0-x86_64.xfs.gpt.qcow2",
		Name:       "Amazon Linux",
		Version:    "2.0",
		PVCPrefix:  "amzn-2-",
	},
	{
		VMImageURI: "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img",
		Name:       "Ubuntu",
		Version:    "20.04",
		PVCPrefix:  "ubuntu-20-",
	},
}
