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
	_ "github.com/replicatedhq/troubleshoot/pkg/apis" // runs the init addon for troubleshoot schema
	troubleshootv1beta2 "github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type InstallerSpec struct {
	Kubernetes      *Kubernetes      `json:"kubernetes,omitempty" yaml:"kubernetes,omitempty"`
	RKE2            *RKE2            `json:"rke2,omitempty" yaml:"rke2,omitempty"`
	K3S             *K3S             `json:"k3s,omitempty" yaml:"k3s,omitempty"`
	Docker          *Docker          `json:"docker,omitempty" yaml:"docker,omitempty"`
	Weave           *Weave           `json:"weave,omitempty" yaml:"weave,omitempty"`
	Antrea          *Antrea          `json:"antrea,omitempty" yaml:"antrea,omitempty"`
	Calico          *Calico          `json:"calico,omitempty" yaml:"calico,omitempty"`
	Contour         *Contour         `json:"contour,omitempty" yaml:"contour,omitempty"`
	Rook            *Rook            `json:"rook,omitempty" yaml:"rook,omitempty"`
	Registry        *Registry        `json:"registry,omitempty" yaml:"registry,omitempty"`
	Prometheus      *Prometheus      `json:"prometheus,omitempty" yaml:"prometheus,omitempty"`
	Fluentd         *Fluentd         `json:"fluentd,omitempty" yaml:"fluentd,omitempty"`
	Kotsadm         *Kotsadm         `json:"kotsadm,omitempty" yaml:"kotsadm,omitempty"`
	Velero          *Velero          `json:"velero,omitempty" yaml:"velero,omitempty"`
	Minio           *Minio           `json:"minio,omitempty" yaml:"minio,omitempty"`
	OpenEBS         *OpenEBS         `json:"openebs,omitempty" yaml:"openebs,omitempty"`
	Kurl            *Kurl            `json:"kurl,omitempty" yaml:"kurl,omitempty"`
	SelinuxConfig   *SelinuxConfig   `json:"selinuxConfig,omitempty" yaml:"selinuxConfig,omitempty"`
	IptablesConfig  *IptablesConfig  `json:"iptablesConfig,omitempty" yaml:"iptablesConfig,omitempty"`
	FirewalldConfig *FirewalldConfig `json:"firewalldConfig,omitempty" yaml:"firewalldConfig,omitempty"`
	Ekco            *Ekco            `json:"ekco,omitempty" yaml:"ekco,omitempty"`
	Containerd      *Containerd      `json:"containerd,omitempty" yaml:"containerd,omitempty"`
	Collectd        *Collectd        `json:"collectd,omitempty" yaml:"collectd,omitempty"`
	CertManager     *CertManager     `json:"certManager,omitempty" yaml:"certManager,omitempty"`
	MetricsServer   *MetricsServer   `json:"metricsServer,omitempty" yaml:"metricsServer,omitempty"`
	Helm            *Helm            `json:"helm,omitempty" yaml:"helm,omitempty"`
	Longhorn        *Longhorn        `json:"longhorn,omitempty" yaml:"longhorn,omitempty"`
	Sonobuoy        *Sonobuoy        `json:"sonobuoy,omitempty" yaml:"sonobuoy,omitempty"`
	UFWConfig       *UFWConfig       `json:"ufwConfig,omitempty" yaml:"ufwConfig,omitempty"`
	Goldpinger      *Goldpinger      `json:"goldpinger,omitempty" yaml:"goldpinger,omitempty"`
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
	ApplicationNamespace    string `json:"applicationNamespace,omitempty" yaml:"applicationNamespace,omitempty"`
	ApplicationSlug         string `json:"applicationSlug,omitempty" yaml:"applicationSlug,omitempty"`
	ApplicationVersionLabel string `json:"applicationVersionLabel,omitempty" yaml:"applicationVersionLabel,omitempty"`
	Hostname                string `json:"hostname,omitempty" yaml:"hostname,omitempty"`
	S3Override              string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	DisableS3               bool   `json:"disableS3,omitempty" yaml:"disableS3,omitempty"`
	UiBindPort              int    `json:"uiBindPort,omitempty" yaml:"uiBindPort,omitempty"`
	Version                 string `json:"version" yaml:"version"`
}

type Kubernetes struct {
	BootstrapToken           string `json:"bootstrapToken,omitempty" yaml:"bootstrapToken,omitempty"`
	BootstrapTokenTTL        string `json:"bootstrapTokenTTL,omitempty" yaml:"bootstrapTokenTTL,omitempty"`
	CertKey                  string `json:"certKey,omitempty" yaml:"certKey,omitempty"`
	ControlPlane             bool   `json:"controlPlane,omitempty" yaml:"controlPlane,omitempty"`
	HACluster                bool   `json:"HACluster,omitempty" yaml:"HACluster,omitempty"`
	ContainerLogMaxSize      string `json:"containerLogMaxSize,omitempty" yaml:"containerLogMaxSize,omitempty"`
	ContainerLogMaxFiles     int    `json:"containerLogMaxFiles,omitempty" yaml:"containerLogMaxFiles,omitempty"`
	KubeadmToken             string `json:"kubeadmToken,omitempty" yaml:"kubeadmToken,omitempty"`
	KubeadmTokenCAHash       string `json:"kubeadmTokenCAHash,omitempty" yaml:"kubeadmTokenCAHash,omitempty"`
	LoadBalancerAddress      string `json:"loadBalancerAddress,omitempty" yaml:"loadBalancerAddress,omitempty"`
	MasterAddress            string `json:"masterAddress,omitempty" yaml:"masterAddress,omitempty"`
	S3Override               string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	ServiceCIDR              string `json:"serviceCIDR,omitempty" yaml:"serviceCIDR,omitempty"`
	ServiceCidrRange         string `json:"serviceCidrRange,omitempty" yaml:"serviceCidrRange,omitempty"`
	UseStandardNodePortRange bool   `json:"useStandardNodePortRange,omitempty" yaml:"useStandardNodePortRange,omitempty"`
	KubernetesReserved       bool   `json:"kubernetesReserved,omitempty" yaml:"kubernetesReserved,omitempty"`
	EvictionThreshold        string `json:"evictionThreshold,omitempty" yaml:"evictionThreshold,omitempty"`
	Version                  string `json:"version" yaml:"version"`
	CisCompliance            bool   `json:"cisCompliance,omitempty" yaml:"cisCompliance,omitempty"`
}

type Kurl struct {
	AdditionalNoProxyAddresses   []string                           `json:"additionalNoProxyAddresses,omitempty" yaml:"additionalNoProxyAddresses,omitempty"`
	Airgap                       bool                               `json:"airgap,omitempty" yaml:"airgap,omitempty"`
	HostnameCheck                string                             `json:"hostnameCheck,omitempty" yaml:"hostnameCheck,omitempty"`
	IgnoreRemoteLoadImagesPrompt bool                               `json:"ignoreRemoteLoadImagesPrompt,omitempty" yaml:"ignoreRemoteLoadImagesPrompt,omitempty"`
	IgnoreRemoteUpgradePrompt    bool                               `json:"ignoreRemoteUpgradePrompt,omitempty" yaml:"ignoreRemoteUpgradePrompt,omitempty"`
	InstallerVersion             string                             `json:"installerVersion,omitempty" yaml:"installerVersion,omitempty"`
	LicenseURL                   string                             `json:"licenseURL,omitempty" yaml:"licenseURL,omitempty"`
	Nameserver                   string                             `json:"nameserver,omitempty" yaml:"nameserver,omitempty"`
	NoProxy                      bool                               `json:"noProxy,omitempty" yaml:"noProxy,omitempty"`
	HostPreflights               *troubleshootv1beta2.HostPreflight `json:"hostPreflights,omitempty" yaml:"hostPreflights,omitempty"`
	HostPreflightIgnore          bool                               `json:"hostPreflightIgnore,omitempty" yaml:"hostPreflightIgnore,omitempty"`
	HostPreflightEnforceWarnings bool                               `json:"hostPreflightEnforceWarnings,omitempty" yaml:"hostPreflightEnforceWarnings,omitempty"`
	PrivateAddress               string                             `json:"privateAddress,omitempty" yaml:"privateAddress,omitempty"`
	ProxyAddress                 string                             `json:"proxyAddress,omitempty" yaml:"proxyAddress,omitempty"`
	PublicAddress                string                             `json:"publicAddress,omitempty" yaml:"publicAddress,omitempty"`
	SkipSystemPackageInstall     bool                               `json:"skipSystemPackageInstall,omitempty" yaml:"skipSystemPackageInstall,omitempty"`
	ExcludeBuiltinHostPreflights bool                               `json:"excludeBuiltinHostPreflights,omitempty" yaml:"excludeBuiltinHostPreflights,omitempty"`
	IPv6                         bool                               `json:"ipv6,omitempty" yaml:"ipv6,omitempty"`
}

type Minio struct {
	ClaimSize  string `json:"claimSize,omitempty" yaml:"claimSize,omitempty"`
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
	S3Override  string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version     string `json:"version" yaml:"version"`
	ServiceType string `json:"serviceType,omitempty" yaml:"serviceType,omitempty"`
}

type Registry struct {
	PublishPort int    `json:"publishPort,omitempty" yaml:"publishPort,omitempty"`
	S3Override  string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version     string `json:"version" yaml:"version"`
}

type RKE2 struct {
	Version string `json:"version" yaml:"version"`
}

type K3S struct {
	Version string `json:"version" yaml:"version"`
}

type Rook struct {
	BlockDeviceFilter          string `json:"blockDeviceFilter,omitempty" yaml:"blockDeviceFilter,omitempty"`
	BypassUpgradeWarning       bool   `json:"bypassUpgradeWarning,omitempty" yaml:"bypassUpgradeWarning,omitempty"`
	CephReplicaCount           int    `json:"cephReplicaCount,omitempty" yaml:"cephReplicaCount,omitempty"`
	IsBlockStorageEnabled      bool   `json:"isBlockStorageEnabled,omitempty" yaml:"isBlockStorageEnabled,omitempty"`
	IsSharedFilesystemDisabled bool   `json:"isSharedFilesystemDisabled,omitempty" yaml:"isSharedFilesystemDisabled,omitempty"`
	S3Override                 string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	StorageClassName           string `json:"storageClassName,omitempty" yaml:"storageClassName,omitempty"`
	HostpathRequiresPrivileged bool   `json:"hostpathRequiresPrivileged,omitempty" yaml:"hostpathRequiresPrivileged,omitempty"`
	Version                    string `json:"version" yaml:"version"`
}

type Velero struct {
	S3Override               string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Namespace                string `json:"namespace,omitempty" yaml:"namespace,omitempty"`
	DisableCLI               bool   `json:"disableCLI,omitempty" yaml:"disableCLI,omitempty"`
	DisableRestic            bool   `json:"disableRestic,omitempty" yaml:"disableRestic,omitempty"`
	LocalBucket              string `json:"localBucket,omitempty" yaml:"localBucket,omitempty"`
	ResticRequiresPrivileged bool   `json:"resticRequiresPrivileged,omitempty" yaml:"resticRequiresPrivileged,omitempty"`
	Version                  string `json:"version" yaml:"version"`
}

type Weave struct {
	IsEncryptionDisabled bool   `json:"isEncryptionDisabled,omitempty" yaml:"isEncryptionDisabled,omitempty"`
	PodCIDR              string `json:"podCIDR,omitempty" yaml:"podCIDR,omitempty"`
	PodCidrRange         string `json:"podCidrRange,omitempty" yaml:"podCidrRange,omitempty"`
	S3Override           string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version              string `json:"version" yaml:"version"`
	// NoMasqLocal if not present defaults to true, which will expose the original client IP address in the
	// X-Forwarded-For header.
	NoMasqLocal *bool `json:"noMasqLocal,omitempty" yaml:"noMasqLocal,omitempty"`
}

type Antrea struct {
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
	MinReadyMasterNodeCount     int      `json:"minReadyMasterNodeCount,omitempty" yaml:"minReadyMasterNodeCount,omitempty"`
	MinReadyWorkerNodeCount     int      `json:"minReadyWorkerNodeCount,omitempty" yaml:"minReadyWorkerNodeCount,omitempty"`
	NodeUnreachableToleration   string   `json:"nodeUnreachableToleration,omitempty" yaml:"nodeUnreachableToleration,omitempty"`
	RookShouldUseAllNodes       bool     `json:"rookShouldUseAllNodes,omitempty" yaml:"rookShouldUseAllNodes,omitempty"`
	S3Override                  string   `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	ShouldDisableRebootServices bool     `json:"shouldDisableRebootServices,omitempty" yaml:"shouldDisableRebootServices,omitempty"`
	ShouldDisableClearNodes     bool     `json:"shouldDisableClearNodes,omitempty" yaml:"shouldDisableClearNodes,omitempty"`
	ShouldEnablePurgeNodes      bool     `json:"shouldEnablePurgeNodes,omitempty" yaml:"shouldEnablePurgeNodes,omitempty"`
	Version                     string   `json:"version" yaml:"version"`
	AutoUpgradeSchedule         string   `json:"autoUpgradeSchedule,omitempty" yaml:"autoUpgradeSchedule,omitempty"`
	EnableInternalLoadBalancer  bool     `json:"enableInternalLoadBalancer,omitempty" yaml:"enableInternalLoadBalancer,omitempty"`
	PodImageOverrides           []string `json:"podImageOverrides,omitempty" yaml:"podImageOverrides,omitempty"`
}

type Calico struct {
	S3Override string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version    string `json:"version" yaml:"version"`
}

type Containerd struct {
	S3Override     string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	TomlConfig     string `json:"tomlConfig,omitempty" yaml:"tomlConfig,omitempty"`
	PreserveConfig bool   `json:"preserveConfig,omitempty" yaml:"preserveConfig,omitempty"`
	Version        string `json:"version" yaml:"version"`
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

type Helm struct {
	HelmfileSpec     string   `json:"helmfileSpec" yaml:"helmfileSpec"`
	AdditionalImages []string `json:"additionalImages,omitempty" yaml:"additionalImages,omitempty"`
}

type Longhorn struct {
	S3Override                        string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	StorageOverProvisioningPercentage int    `json:"storageOverProvisioningPercentage,omitempty" yaml:"storageOverProvisioningPercentage,omitempty"`
	Version                           string `json:"version" yaml:"version"`
	UiBindPort                        int    `json:"uiBindPort,omitempty" yaml:"uiBindPort,omitempty"`
	UiReplicaCount                    int    `json:"uiReplicaCount,omitempty" yaml:"uiReplicaCount,omitempty"`
}

type Sonobuoy struct {
	S3Override string `json:"s3Override,omitempty" yaml:"s3Override,omitempty"`
	Version    string `json:"version" yaml:"version"`
}

type UFWConfig struct {
	BypassUFWWarning bool `json:"bypassUFWWarning,omitempty" yaml:"bypassUFWWarning,omitempty"`
	DisableUFW       bool `json:"disableUFW,omitempty" yaml:"disableUFW,omitempty"`
	HardFailOnUFW    bool `json:"hardFailOnUFW,omitempty" yaml:"hardFailOnUFW,omitempty"`
}

type Goldpinger struct {
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
