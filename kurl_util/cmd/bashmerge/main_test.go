package main

import (
	"testing"

	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func Test_parseBashFlags(t *testing.T) {
	tests := []struct {
		name            string
		oldInstaller    *kurlv1beta1.Installer
		mergedInstaller *kurlv1beta1.Installer
		bashFlags       string
		wantError       bool
	}{
		{
			name: "All proper flags and values new fields",
			oldInstaller: &kurlv1beta1.Installer{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "foo",
					Namespace: "default",
				},
				Spec: kurlv1beta1.InstallerSpec{},
			},
			mergedInstaller: &kurlv1beta1.Installer{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "foo",
					Namespace: "default",
				},
				Spec: kurlv1beta1.InstallerSpec{
					Docker: kurlv1beta1.Docker{
						DockerRegistryIP: "1.1.1.1",
						PreserveConfig:   true,
					},
					FirewalldConfig: kurlv1beta1.FirewalldConfig{
						PreserveConfig: true,
					},
					IptablesConfig: kurlv1beta1.IptablesConfig{
						PreserveConfig: true,
					},
					Kubernetes: kurlv1beta1.Kubernetes{
						MasterAddress:       "1.1.1.1",
						HACluster:           true,
						ControlPlane:        true,
						KubeadmToken:        "token",
						KubeadmTokenCAHash:  "hash",
						LoadBalancerAddress: "1.1.1.1",
						Version:             "1.18.1",
						CertKey:             "secret",
					},
					Kurl: kurlv1beta1.Kurl{
						Airgap:        true,
						PublicAddress: "1.1.1.1",
						AdditionalNoProxyAddresses: []string{
							"10.96.0.0/22",
							"10.32.0.0/22",
						},
					},
					SelinuxConfig: kurlv1beta1.SelinuxConfig{
						PreserveConfig: true,
					},
				},
			},
			bashFlags: "additional-no-proxy-addresses=10.96.0.0/22,10.32.0.0/22 " +
				"airgap " +
				"cert-key=secret " +
				"control-plane " +
				"docker-registry-ip=1.1.1.1 " +
				"ha " +
				"preserve-docker-config " +
				"preserve-firewalld-config " +
				"preserve-iptables-config " +
				"preserve-selinux-config " +
				"kubeadm-token=token " +
				"kubeadm-token-ca-hash=hash " +
				"kubernetes-master-address=1.1.1.1 " +
				"kubernetes-version=1.18.1 " +
				"installer-spec-file=in.yaml " +
				"load-balancer-address=1.1.1.1 " +
				"public-address=1.1.1.1",
			wantError: false,
		},
		{
			name: "All proper flags and values replace fields except additional-no-proxy-addresses appends",
			oldInstaller: &kurlv1beta1.Installer{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "foo",
					Namespace: "default",
				},
				Spec: kurlv1beta1.InstallerSpec{
					Docker: kurlv1beta1.Docker{
						DockerRegistryIP: "2.2.2.2",
					},
					Kubernetes: kurlv1beta1.Kubernetes{
						MasterAddress:       "2.2.2.2",
						HACluster:           false,
						ControlPlane:        false,
						KubeadmToken:        "badtoken",
						KubeadmTokenCAHash:  "badhash",
						LoadBalancerAddress: "2.2.2.2",
						Version:             "1.15.0",
						CertKey:             "badsecret",
					},
					Kurl: kurlv1beta1.Kurl{
						Airgap:                     false,
						PublicAddress:              "2.2.2.2",
						AdditionalNoProxyAddresses: []string{"registry.internal"},
					},
				},
			},
			mergedInstaller: &kurlv1beta1.Installer{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "foo",
					Namespace: "default",
				},
				Spec: kurlv1beta1.InstallerSpec{
					Docker: kurlv1beta1.Docker{
						DockerRegistryIP: "1.1.1.1",
						PreserveConfig:   true,
					},
					FirewalldConfig: kurlv1beta1.FirewalldConfig{
						PreserveConfig: true,
					},
					IptablesConfig: kurlv1beta1.IptablesConfig{
						PreserveConfig: true,
					},
					Kubernetes: kurlv1beta1.Kubernetes{
						MasterAddress:       "1.1.1.1",
						HACluster:           true,
						ControlPlane:        true,
						KubeadmToken:        "token",
						KubeadmTokenCAHash:  "hash",
						LoadBalancerAddress: "1.1.1.1",
						Version:             "1.18.1",
						CertKey:             "secret",
					},
					Kurl: kurlv1beta1.Kurl{
						Airgap:        true,
						PublicAddress: "1.1.1.1",
						AdditionalNoProxyAddresses: []string{
							"registry.internal",
							"10.96.0.0/22",
							"10.32.0.0/22",
						},
					},
					SelinuxConfig: kurlv1beta1.SelinuxConfig{
						PreserveConfig: true,
					},
				},
			},
			bashFlags: "additional-no-proxy-addresses=10.96.0.0/22,10.32.0.0/22 " +
				"airgap " +
				"cert-key=secret " +
				"control-plane " +
				"docker-registry-ip=1.1.1.1 " +
				"ha " +
				"preserve-docker-config " +
				"preserve-firewalld-config " +
				"preserve-iptables-config " +
				"preserve-selinux-config " +
				"kubeadm-token=token " +
				"kubeadm-token-ca-hash=hash " +
				"kubernetes-master-address=1.1.1.1 " +
				"kubernetes-version=1.18.1 " +
				"installer-spec-file=in.yaml " +
				"load-balancer-address=1.1.1.1 " +
				"public-address=1.1.1.1",
			wantError: false,
		},
		{
			name: "Proper flag with no value",
			oldInstaller: &kurlv1beta1.Installer{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "foo",
					Namespace: "default",
				},
				Spec: kurlv1beta1.InstallerSpec{},
			},
			mergedInstaller: &kurlv1beta1.Installer{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "foo",
					Namespace: "default",
				},
				Spec: kurlv1beta1.InstallerSpec{},
			},
			bashFlags: "certkey",
			wantError: true,
		},
		{
			name: "Improper flag",
			oldInstaller: &kurlv1beta1.Installer{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "foo",
					Namespace: "default",
				},
				Spec: kurlv1beta1.InstallerSpec{},
			},
			mergedInstaller: &kurlv1beta1.Installer{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "foo",
					Namespace: "default",
				},
				Spec: kurlv1beta1.InstallerSpec{},
			},
			bashFlags: "BaD FlAgS",
			wantError: true,
		},
		{
			name:         "Kubernetes version with v",
			oldInstaller: &kurlv1beta1.Installer{},
			bashFlags:    "kubernetes-version=v1.17.3",
			mergedInstaller: &kurlv1beta1.Installer{
				Spec: kurlv1beta1.InstallerSpec{
					Kubernetes: kurlv1beta1.Kubernetes{
						Version: "1.17.3",
					},
				},
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			req := require.New(t)

			err := parseBashFlags(test.oldInstaller, test.bashFlags)
			if test.wantError {
				req.Error(err)
			} else {
				req.NoError(err)
			}

			assert.Equal(t, test.oldInstaller, test.mergedInstaller)
		})
	}
}
