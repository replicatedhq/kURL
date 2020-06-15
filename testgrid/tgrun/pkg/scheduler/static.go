package scheduler

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

var operatingSystems = []types.OperatingSystemImage{
	{
		VMImageURI: "https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img",
		Name:       "Ubuntu",
		Version:    "18.04",
		PVCPrefix:  "ubuntu-18-",
	},
}

var testSpecs = []types.InstallerSpec{
	latestRecommendedRook,
	latestRecommendedOpenEBS,
}

var latestRecommendedRook = types.InstallerSpec{
	Kubernetes: kurlv1beta1.Kubernetes{
		Version: "1.17.3",
	},
	Weave: &kurlv1beta1.Weave{
		Version: "2.6.4",
	},
	Rook: &kurlv1beta1.Rook{
		Version: "1.0.4",
	},
	Contour: &kurlv1beta1.Contour{
		Version: "1.0.1",
	},
	Docker: &kurlv1beta1.Docker{
		Version: "19.03.4",
	},
	Prometheus: &kurlv1beta1.Prometheus{
		Version: "0.33.0",
	},
	Registry: &kurlv1beta1.Registry{
		Version: "2.7.1",
	},
	Velero: &kurlv1beta1.Velero{
		Version: "1.2.0",
	},
	Kotsadm: &kurlv1beta1.Kotsadm{
		Version: "1.16.0",
	},
}

var latestRecommendedOpenEBS = types.InstallerSpec{
	Kubernetes: kurlv1beta1.Kubernetes{
		Version: "1.17.3",
	},
	Weave: &kurlv1beta1.Weave{
		Version: "2.6.4",
	},
	OpenEBS: &kurlv1beta1.OpenEBS{
		Version: "1.6.0",
	},
	Contour: &kurlv1beta1.Contour{
		Version: "1.0.1",
	},
	Docker: &kurlv1beta1.Docker{
		Version: "19.03.4",
	},
	Prometheus: &kurlv1beta1.Prometheus{
		Version: "0.33.0",
	},
	Registry: &kurlv1beta1.Registry{
		Version: "2.7.1",
	},
	Velero: &kurlv1beta1.Velero{
		Version: "1.2.0",
	},
	Kotsadm: &kurlv1beta1.Kotsadm{
		Version: "1.16.0",
	},
}
