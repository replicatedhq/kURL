/*
Copyright 2020 Replicated Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1beta1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type InstallerSpec struct {
	Kubernetes      Kubernetes      `json:"kubernetes,omitempty"`
	Docker          Docker          `json:"docker,omitempty"`
	Weave           Weave           `json:"weave,omitempty"`
	Calico          Calico          `json:"calico,omitempty"`
	Contour         Contour         `json:"contour,omitempty"`
	Rook            Rook            `json:"rook,omitempty"`
	Registry        Registry        `json:"registry,omitempty"`
	Prometheus      Prometheus      `json:"prometheus,omitempty"`
	Fluentd         Fluentd         `json:"fluentd,omitempty"`
	Kotsadm         Kotsadm         `json:"kotsadm,omitempty"`
	Velero          Velero          `json:"velero,omitempty"`
	Minio           Minio           `json:"minio,omitempty"`
	OpenEBS         OpenEBS         `json:"openebs,omitempty"`
	Kurl            Kurl            `json:"kurl,omitempty"`
	SelinuxConfig   SelinuxConfig   `json:"selinuxConfig,omitempty"`
	IptablesConfig  IptablesConfig  `json:"iptablesConfig,omitempty"`
	FirewalldConfig FirewalldConfig `json:"firewalldConfig,omitempty"`
	Ekco            Ekco            `json:"ekco,omitempty"`
	Containerd      Containerd      `json:"containerd,omitempty"`
	Collectd        Collectd        `json:"collectd,omitempty"`
	CertManager     CertManager     `json:"certManager,omitempty"`
	MetricsServer   MetricsServer   `json:"metricsServer,omitempty"`
}

type Contour struct {
	Version                   string `json:"version"`
	TLSMinimumProtocolVersion string `json:"tlsMinimumProtocolVersion,omitempty"`
}

type Docker struct {
	BypassStorageDriverWarning bool   `json:"bypassStorageDriverWarning,omitempty"`
	DaemonConfig               string `json:"daemonConfig,omitempty"`
	DockerRegistryIP           string `json:"dockerRegistryIP,omitempty"`
	HardFailOnLoopback         bool   `json:"hardFailOnLoopback,omitempty"`
	NoCEOnEE                   bool   `json:"noCEOnEE,omitempty"`
	PreserveConfig             bool   `json:"preserveConfig,omitempty"`
	Version                    string `json:"version"`
}

type Fluentd struct {
	FullEFKStack    bool   `json:"fullEFKStack,omitempty"`
	Version         string `json:"version"`
	FluentdConfPath string `json:"fluentdConfPath,omitempty"`
}

type Kotsadm struct {
	ApplicationNamespace string `json:"applicationNamespace,omitempty"`
	ApplicationSlug      string `json:"applicationSlug,omitempty"`
	Hostname             string `json:"hostname,omitempty"`
	UiBindPort           int    `json:"uiBindPort,omitempty"`
	Version              string `json:"version"`
}

type Kubernetes struct {
	BootstrapToken           string `json:"bootstrapToken,omitempty"`
	BootstrapTokenTTL        string `json:"bootstrapTokenTTL,omitempty"`
	CertKey                  string `json:"certKey,omitempty"`
	ControlPlane             bool   `json:"controlPlane,omitempty"`
	HACluster                bool   `json:"HACluster,omitempty"`
	KubeadmToken             string `json:"kubeadmToken,omitempty"`
	KubeadmTokenCAHash       string `json:"kubeadmTokenCAHash,omitempty"`
	LoadBalancerAddress      string `json:"loadBalancerAddress,omitempty"`
	MasterAddress            string `json:"masterAddress,omitempty"`
	ServiceCIDR              string `json:"serviceCIDR,omitempty"`
	ServiceCidrRange         string `json:"serviceCidrRange,omitempty"`
	UseStandardNodePortRange bool   `json:"useStandardNodePortRange,omitempty"`
	Version                  string `json:"version"`
}

type Kurl struct {
	Airgap                     bool     `json:"airgap,omitempty"`
	HostnameCheck              string   `json:"hostnameCheck,omitempty"`
	ProxyAddress               string   `json:"proxyAddress,omitempty"`
	AdditionalNoProxyAddresses []string `json:"additionalNoProxyAddresses,omitempty"`
	NoProxy                    bool     `json:"noProxy,omitempty"`
	PublicAddress              string   `json:"publicAddress,omitempty"`
	PrivateAddress             string   `json:"privateAddress,omitempty"`
	Nameserver                 string   `json:"nameserver,omitempty"`
}

type Minio struct {
	Namespace string `json:"namespace,omitempty"`
	Version   string `json:"version"`
}

type OpenEBS struct {
	CstorStorageClassName   string `json:"cstorStorageClassName,omitempty"`
	IsCstorEnabled          bool   `json:"isCstorEnabled,omitempty"`
	IsLocalPVEnabled        bool   `json:"isLocalPVEnabled,omitempty"`
	LocalPVStorageClassName string `json:"localPVStorageClassName,omitempty"`
	Namespace               string `json:"namespace,omitempty"`
	Version                 string `json:"version"`
}

type Prometheus struct {
	Version string `json:"version"`
}

type Registry struct {
	PublishPort int    `json:"publishPort,omitempty"`
	Version     string `json:"version"`
}

type Rook struct {
	BlockDeviceFilter     string `json:"blockDeviceFilter,omitempty"`
	CephReplicaCount      int    `json:"cephReplicaCount,omitempty"`
	IsBlockStorageEnabled bool   `json:"isBlockStorageEnabled,omitempty"`
	StorageClassName      string `json:"storageClassName,omitempty"`
	Version               string `json:"version"`
}

type Velero struct {
	DisableCLI    bool   `json:"disableCLI,omitempty"`
	DisableRestic bool   `json:"disableRestic,omitempty"`
	LocalBucket   string `json:"localBucket,omitempty"`
	Namespace     string `json:"namespace,omitempty"`
	Version       string `json:"version"`
}

type Weave struct {
	IsEncryptionDisabled bool   `json:"isEncryptionDisabled,omitempty"`
	PodCIDR              string `json:"podCIDR,omitempty"`
	PodCidrRange         string `json:"podCidrRange,omitempty"`
	Version              string `json:"version"`
}

type SelinuxConfig struct {
	ChconCmds      [][]string `json:"chconCmds,omitempty"`
	DisableSelinux bool       `json:"disableSelinux,omitempty"`
	PreserveConfig bool       `json:"preserveConfig,omitempty"`
	Selinux        string     `json:"selinux,omitempty"`
	SemanageCmds   [][]string `json:"semanageCmds,omitempty"`
	Type           string     `json:"type,omitempty"`
}

type IptablesConfig struct {
	IptablesCmds   [][]string `json:"iptablesCmds,omitempty"`
	PreserveConfig bool       `json:"preserveConfig,omitempty"`
}

type FirewalldConfig struct {
	BypassFirewalldWarning bool       `json:"bypassFirewalldWarning,omitempty"`
	DisableFirewalld       bool       `json:"disableFirewalld,omitempty"`
	Firewalld              string     `json:"firewalld,omitempty"`
	FirewalldCmds          [][]string `json:"firewalldCmds,omitempty"`
	HardFailOnFirewalld    bool       `json:"hardFailOnFirewalld,omitempty"`
	PreserveConfig         bool       `json:"preserveConfig,omitempty"`
}

type Ekco struct {
	MinReadyMasterNodeCount     int    `json:"minReadyMasterNodeCount,omitempty"`
	MinReadyWorkerNodeCount     int    `json:"minReadyWorkerNodeCount,omitempty"`
	NodeUnreachableToleration   string `json:"nodeUnreachableToleration,omitempty"`
	RookShouldUseAllNodes       bool   `json:"rookShouldUseAllNodes,omitempty"`
	ShouldDisableRebootServices bool   `json:"shouldDisableRebootServices,omitempty"`
	ShouldDisableClearNodes     bool   `json:"shouldDisableClearNodes,omitempty"`
	ShouldEnablePurgeNodes      bool   `json:"shouldEnablePurgeNodes,omitempty"`
	Version                     string `json:"version"`
	AutoUpgradeSchedule         string `json:"autoUpgradeSchedule,omitempty"`
}

type Calico struct {
	Version string `json:"version"`
}

type Containerd struct {
	Version string `json:"version"`
}

type Collectd struct {
	Version string `json:"version"`
}

type CertManager struct {
	Version string `json:"version"`
}

type MetricsServer struct {
	Version string `json:"version"`
}

// InstallerStatus defines the observed state of Installer
type InstallerStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
}

// +genclient
// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object

// Installer is the Schema for the installers API
// +k8s:openapi-gen=true
type Installer struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   InstallerSpec   `json:"spec,omitempty"`
	Status InstallerStatus `json:"status,omitempty"`
}

// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object

// InstallerList contains a list of Installer
type InstallerList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Installer `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Installer{}, &InstallerList{})
}
