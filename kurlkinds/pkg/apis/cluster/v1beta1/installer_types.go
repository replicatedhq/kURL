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
	RKE2            RKE2            `json:"rke2,omitempty"`
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
	S3Override                string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version                   string `json:"version" yaml:"version"`
	TLSMinimumProtocolVersion string `json:"tlsMinimumProtocolVersion,omitempty" yaml:"tlsMinimumProtocolVersion,omitempty"`
	HTTPPort                  int    `json:"httpPort,omitempty" yaml:"httpPort,omitempty"`
	HTTPSPort                 int    `json:"httpsPort,omitempty" yaml:"httpsPort,omitempty"`
}

type Docker struct {
	BypassStorageDriverWarning bool   `json:"bypassStorageDriverWarning,omitempty" yaml:"bypassStorageDriverWarning,omitempty"`
	DaemonConfig               string `json:"daemonConfig,omitempty" yaml:"daemonConfig,omitempty"`
	DockerRegistryIP           string `json:"dockerRegistryIP,omitempty" yaml:"dockerRegistryIP,omitempty"`
	HardFailOnLoopback         bool   `json:"hardFailOnLoopback,omitempty" yaml:"hardFailOnLoopback,omitempty"`
	NoCEOnEE                   bool   `json:"noCEOnEE,omitempty" yaml:"noCEOnEE,omitempty"`
	PreserveConfig             bool   `json:"preserveConfig,omitempty" yaml:"preserveConfig,omitempty"`
	S3Override                 string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version                    string `json:"version" yaml:"version"`
}

type Fluentd struct {
	FullEFKStack    bool   `json:"fullEFKStack,omitempty" yaml:"fullEFKStack,omitempty"`
	S3Override      string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version         string `json:"version" yaml:"version"`
	FluentdConfPath string `json:"fluentdConfPath,omitempty" yaml:"fluentdConfPath,omitempty"`
}

type Kotsadm struct {
	ApplicationNamespace string `json:"applicationNamespace,omitempty" yaml:"applicationNamespace,omitempty"`
	ApplicationSlug      string `json:"applicationSlug,omitempty" yaml:"applicationSlug,omitempty"`
	Hostname             string `json:"hostname,omitempty" yaml:"hostname,omitempty"`
	S3Override           string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	UiBindPort           int    `json:"uiBindPort,omitempty" yaml:"uiBindPort,omitempty"`
	Version              string `json:"version" yaml:"version"`
}

type Kubernetes struct {
	BootstrapToken           string `json:"bootstrapToken,omitempty" yaml:"bootstrapToken,omitempty"`
	BootstrapTokenTTL        string `json:"bootstrapTokenTTL,omitempty" yaml:"bootstrapTokenTTL,omitempty"`
	CertKey                  string `json:"certKey,omitempty" yaml:"certKey,omitempty"`
	ControlPlane             bool   `json:"controlPlane,omitempty" yaml:"controlPlane,omitempty"`
	HACluster                bool   `json:"HACluster,omitempty" yaml:"HACluster,omitempty"`
	KubeadmToken             string `json:"kubeadmToken,omitempty" yaml:"kubeadmToken,omitempty"`
	KubeadmTokenCAHash       string `json:"kubeadmTokenCAHash,omitempty" yaml:"kubeadmTokenCAHash,omitempty"`
	LoadBalancerAddress      string `json:"loadBalancerAddress,omitempty" yaml:"loadBalancerAddress,omitempty"`
	MasterAddress            string `json:"masterAddress,omitempty" yaml:"masterAddress,omitempty"`
	S3Override               string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	ServiceCIDR              string `json:"serviceCIDR,omitempty" yaml:"serviceCIDR,omitempty"`
	ServiceCidrRange         string `json:"serviceCidrRange,omitempty" yaml:"serviceCidrRange,omitempty"`
	UseStandardNodePortRange bool   `json:"useStandardNodePortRange,omitempty" yaml:"useStandardNodePortRange,omitempty"`
	Version                  string `json:"version" yaml:"version"`
}

type Kurl struct {
	Airgap                     bool     `json:"airgap,omitempty" yaml:"airgap,omitempty"`
	HostnameCheck              string   `json:"hostnameCheck,omitempty" yaml:"hostnameCheck,omitempty"`
	ProxyAddress               string   `json:"proxyAddress,omitempty" yaml:"proxyAddress,omitempty"`
	AdditionalNoProxyAddresses []string `json:"additionalNoProxyAddresses,omitempty" yaml:"proxyAddress,omitempty"`
	NoProxy                    bool     `json:"noProxy,omitempty" yaml:"noProxy,omitempty"`
	PublicAddress              string   `json:"publicAddress,omitempty" yaml:"publicAddress,omitempty"`
	PrivateAddress             string   `json:"privateAddress,omitempty" yaml:"privateAddress,omitempty"`
	Nameserver                 string   `json:"nameserver,omitempty" yaml:"nameserver,omitempty"`
}

type Minio struct {
	Namespace  string `json:"namespace,omitempty" yaml:"namespace,omitempty"`
	S3Override string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	HostPath   string `json:"hostPath,omitempty" yaml:"hostPath,omitempty"`
	Version    string `json:"version" yaml:"version"`
}

type OpenEBS struct {
	CstorStorageClassName   string `json:"cstorStorageClassName,omitempty" yaml:"cstorStorageClassName,omitempty"`
	IsCstorEnabled          bool   `json:"isCstorEnabled,omitempty" yaml:"isCstorEnabled,omitempty"`
	IsLocalPVEnabled        bool   `json:"isLocalPVEnabled,omitempty" yaml:"isLocalPVEnabled,omitempty"`
	LocalPVStorageClassName string `json:"localPVStorageClassName,omitempty" yaml:"localPVStorageClassName,omitempty"`
	Namespace               string `json:"namespace,omitempty" yaml:"namespace,omitempty"`
	S3Override              string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version                 string `json:"version" yaml:"version"`
}

type Prometheus struct {
	S3Override string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version    string `json:"version" yaml:"version"`
}

type Registry struct {
	PublishPort int    `json:"publishPort,omitempty" yaml:"publishPort,omitempty"`
	S3Override  string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version     string `json:"version" yaml:"version"`
}

type RKE2 struct {
	Version string `json:"version" yaml:"version"`
}

type Rook struct {
	BlockDeviceFilter     string `json:"blockDeviceFilter,omitempty" yaml:"blockDeviceFilter,omitempty"`
	CephReplicaCount      int    `json:"cephReplicaCount,omitempty" yaml:"cephReplicaCount,omitempty"`
	IsBlockStorageEnabled bool   `json:"isBlockStorageEnabled,omitempty" yaml:"isBlockStorageEnabled,omitempty"`
	S3Override            string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	StorageClassName      string `json:"storageClassName,omitempty" yaml:"storageClassName,omitempty"`
	Version               string `json:"version" yaml:"version"`
}

type Velero struct {
	DisableCLI    bool   `json:"disableCLI,omitempty" yaml:"disableCLI,omitempty"`
	DisableRestic bool   `json:"disableRestic,omitempty" yaml:"disableRestic,omitempty"`
	LocalBucket   string `json:"localBucket,omitempty" yaml:"localBucket,omitempty"`
	Namespace     string `json:"namespace,omitempty" yaml:"namespace,omitempty"`
	S3Override    string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version       string `json:"version" yaml:"version"`
}

type Weave struct {
	IsEncryptionDisabled bool   `json:"isEncryptionDisabled,omitempty" yaml:"isEncryptionDisabled,omitempty"`
	PodCIDR              string `json:"podCIDR,omitempty" yaml:"podCIDR,omitempty"`
	PodCidrRange         string `json:"podCidrRange,omitempty" yaml:"podCidrRange,omitempty"`
	S3Override           string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version              string `json:"version" yaml:"version"`
}

type SelinuxConfig struct {
	ChconCmds      [][]string `json:"chconCmds,omitempty" yaml:"chconCmds,omitempty"`
	DisableSelinux bool       `json:"disableSelinux,omitempty" yaml:"disableSelinux,omitempty"`
	PreserveConfig bool       `json:"preserveConfig,omitempty" yaml:"preserveConfig,omitempty"`
	Selinux        string     `json:"selinux,omitempty" yaml:"selinux,omitempty"`
	SemanageCmds   [][]string `json:"semanageCmds,omitempty" yaml:"semanageCmds,omitempty"`
	Type           string     `json:"type,omitempty" yaml:"type,omitempty"`
}

type IptablesConfig struct {
	IptablesCmds   [][]string `json:"iptablesCmds,omitempty" yaml:"iptablesCmds,omitempty"`
	PreserveConfig bool       `json:"preserveConfig,omitempty" yaml:"preserveConfig,omitempty"`
}

type FirewalldConfig struct {
	BypassFirewalldWarning bool       `json:"bypassFirewalldWarning,omitempty" yaml:"bypassFirewalldWarning,omitempty"`
	DisableFirewalld       bool       `json:"disableFirewalld,omitempty" yaml:"disableFirewalld,omitempty"`
	Firewalld              string     `json:"firewalld,omitempty" yaml:"firewalld,omitempty"`
	FirewalldCmds          [][]string `json:"firewalldCmds,omitempty" yaml:"firewalldCmds,omitempty"`
	HardFailOnFirewalld    bool       `json:"hardFailOnFirewalld,omitempty" yaml:"hardFailOnFirewalld,omitempty"`
	PreserveConfig         bool       `json:"preserveConfig,omitempty" yaml:"preserveConfig,omitempty"`
}

type Ekco struct {
	MinReadyMasterNodeCount     int    `json:"minReadyMasterNodeCount,omitempty" yaml:"minReadyMasterNodeCount,omitempty"`
	MinReadyWorkerNodeCount     int    `json:"minReadyWorkerNodeCount,omitempty" yaml:"minReadyWorkerNodeCount,omitempty"`
	NodeUnreachableToleration   string `json:"nodeUnreachableToleration,omitempty" yaml:"nodeUnreachableToleration,omitempty"`
	RookShouldUseAllNodes       bool   `json:"rookShouldUseAllNodes,omitempty" yaml:"rookShouldUseAllNodes,omitempty"`
	S3Override                  string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	ShouldDisableRebootServices bool   `json:"shouldDisableRebootServices,omitempty" yaml:"shouldDisableRebootServices,omitempty"`
	ShouldDisableClearNodes     bool   `json:"shouldDisableClearNodes,omitempty" yaml:"shouldDisableClearNodes,omitempty"`
	ShouldEnablePurgeNodes      bool   `json:"shouldEnablePurgeNodes,omitempty" yaml:"shouldEnablePurgeNodes,omitempty"`
	Version                     string `json:"version" yaml:"version"`
	AutoUpgradeSchedule         string `json:"autoUpgradeSchedule,omitempty" yaml:"autoUpgradeSchedule,omitempty"`
}

type Calico struct {
	S3Override string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version    string `json:"version" yaml:"version"`
}

type Containerd struct {
	S3Override string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version    string `json:"version" yaml:"version" yaml:"version" yaml:"version"`
}

type Collectd struct {
	S3Override string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version    string `json:"version" yaml:"version"`
}

type CertManager struct {
	S3Override string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version    string `json:"version" yaml:"version"`
}

type MetricsServer struct {
	S3Override string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version    string `json:"version" yaml:"version"`
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
