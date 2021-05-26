package scheduler

import (
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

var operatingSystems = []types.OperatingSystemImage{
	{
		VMImageURI: "https://cdn.amazonlinux.com/os-images/2.0.20200917.0/kvm/amzn2-kvm-2.0.20200917.0-x86_64.xfs.gpt.qcow2",
		Name:       "Amazon Linux",
		Version:    "2.0",
		ID:         "amzn-20",
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-1708.qcow2",
		Name:       "CentOS",
		Version:    "7.4",
		ID:         "centos-74",
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-2003.qcow2",
		Name:       "CentOS",
		Version:    "7.8",
		ID:         "centos-78",
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-2009.qcow2",
		Name:       "CentOS",
		Version:    "7.9",
		ID:         "centos-79",
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.1.1911-20200113.3.x86_64.qcow2",
		Name:       "CentOS",
		Version:    "8.1",
		ID:         "centos-81",
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2",
		Name:       "CentOS",
		Version:    "8.2",
		ID:         "centos-82",
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.3.2011-20201204.2.x86_64.qcow2",
		Name:       "CentOS",
		Version:    "8.3",
		ID:         "centos-83",
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-2009.qcow2",
		Name:       "Oracle Linux",
		Version:    "7.9",
		ID:         "ol-79",
		PreInit: `
curl -L -o centos2ol.sh https://raw.githubusercontent.com/oracle/centos2ol/main/centos2ol.sh
chmod +x centos2ol.sh
bash centos2ol.sh
`,
	},
	{
		VMImageURI: "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.3.2011-20201204.2.x86_64.qcow2",
		Name:       "Oracle Linux",
		Version:    "8.4",
		ID:         "ol-84",
		PreInit: `
curl -L -o centos2ol.sh https://raw.githubusercontent.com/oracle/centos2ol/main/centos2ol.sh
chmod +x centos2ol.sh
bash centos2ol.sh
`,
	},
	{
		VMImageURI: "https://testgrid-images.s3.amazonaws.com/ubuntu/16.04/ubuntu-16.04-kernel-4.15.0-122-generic.qcow2",
		Name:       "Ubuntu",
		Version:    "16.04",
		ID:         "ubuntu-1604",
	},
	{
		VMImageURI: "https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img",
		Name:       "Ubuntu",
		Version:    "18.04",
		ID:         "ubuntu-1804",
	},
	{
		VMImageURI: "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img",
		Name:       "Ubuntu",
		Version:    "20.04",
		ID:         "ubuntu-2004",
	},
}
