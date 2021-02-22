package instances

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
)

func init() {
	RegisterInstance(
		types.Instance{
			InstallerSpec: types.InstallerSpec{
				Kubernetes: &kurlv1beta1.Kubernetes{
					Version: "latest",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "latest",
				},
				Containerd: &kurlv1beta1.Containerd{
					Version: "latest",
				},
				Helm: &kurlv1beta1.Helm{
					HelmfileSpec: "repositories:\n- name: nginx-stable\n  url: https://helm.nginx.com/stable\nreleases:\n- name: nginx-ingress\n  chart: nginx-stable/nginx-ingress\n  version: ~0.8.0\n  values:\n  - controller:\n      image:\n        tag: 1.9.1\n      service:\n        type: NodePort\n        httpPort:\n          nodePort: 30080\n        httpsPort:\n          nodePort: 30443",
				},
			},
			UpgradeSpec: &types.InstallerSpec{
				Kubernetes: &kurlv1beta1.Kubernetes{
					Version: "latest",
				},
				Weave: &kurlv1beta1.Weave{
					Version: "latest",
				},
				Containerd: &kurlv1beta1.Containerd{
					Version: "latest",
				},
				Helm: &kurlv1beta1.Helm{
					HelmfileSpec: "repositories:\n- name: nginx-stable\n  url: https://helm.nginx.com/stable\nreleases:\n- name: nginx-ingress\n  chart: nginx-stable/nginx-ingress\n  version: ~0.8.0\n  values:\n  - controller:\n      image:\n        tag: 1.10.0\n      service:\n        type: NodePort\n        httpPort:\n          nodePort: 30080\n        httpsPort:\n          nodePort: 30443",
				},
			},
		},
	)
}
