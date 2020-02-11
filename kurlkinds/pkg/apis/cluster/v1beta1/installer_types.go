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

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// InstallerSpec defines the desired state of Installer
type InstallerSpec struct {
	Kubernetes Kubernetes `json:"kubernetes,omitempty"`
	Docker     Docker     `json:"docker,omitempty"`
	Weave      Weave      `json:"weave,omitempty"`
	Contour    Contour    `json:"contour,omitempty"`
	Rook       Rook       `json:"rook,omitempty"`
	Registry   Registry   `json:"registry,omitempty"`
	Prometheus Prometheus `json:"prometheus,omitempty"`
	Fluentd    Fluentd    `json:"fluentd,omitempty"`
	Kotsadm    Kotsadm    `json:"kotsadm,omitempty"`
	Velero     Velero     `json:"velero,omitempty"`
	Flags      Flags      `json:"flags,omitempty"`
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

}

type Flags struct {
	IsKurl bool `json:"isKurl,omitempty"`

	Airgap                        bool   `json:"airgap,omitempty"`
	BypassStorageDriverWarnings   bool   `json:"bypassStorageDriverWarnings,omitempty"`
	BootstrapToken                string `json:"bootstrapToken,omitempty"`
	BootstrapTokenTTL             string `json:"bootstrapTokenTTL,omitempty"`
	CephPoolReplicas              int    `json:"cephPoolReplicas,omitempty"`
	HostnameCheck                 string `json:"hostnameCheck,omitempty"`
	HACluster                     bool   `json:"HACluster,omitempty"`
	HTTPProxy                     string `json:"HTTPProxy,omitempty"`
	IPAllocRange                  string `json:"IPAllocRange,omitempty"`
	LoadBalancerAddress           string `json:"loadBalancerAddress,omitempty"`
	LogLevel                      string `json:"logLevel,omitempty"`
	NoDocker                      bool   `json:"noDocker,omitempty"`
	NoProxy                       bool   `json:"noProxy,omitempty"`
	PublicAddress                 string `json:"publicAddress,omitempty"`
	PrivateAddress                string `json:"privateAddress,omitempty"`
	SkipPull                      bool   `json:"skipPull,omitempty"`
	KubernetesNamespace           string `json:"kubernetesNamespace,omitempty"`
	StorageClass                  string `json:"storageClass,omitempty"`
	NoCEOnEE                      bool   `json:"noCEOnEE,omitempty"`
	HardFailOnLoopback            bool   `json:"hardFailOnLoopback,omitempty"`
	HardFailOnFirewalld           bool   `json:"hardFailOnFirewalld,omitempty"`
	BypassFirewalldWarning        bool   `json:"bypassFirewalldWarning,omitempty"`
	DisableContour                bool   `json:"disableContour,omitempty"`
	DisableRook                   bool   `json:"disableRook,omitempty"`
	DisablePrometheus             bool   `json:"disablePrometheus,omitempty"`
	FullEFKStack                  bool   `json:"fullEFKStack,omitempty"`
	ForceReset                    bool   `json:"forceReset,omitempty"`
	ServiceCIDR                   string `json:"serviceCIDR,omitempty"`
	ClusterDNS                    string `json:"clusterDNS,omitempty"`
	EncryptNetwork                string `json:"encryptNetwork,omitempty"`
	AdditionalNoProxy             string `json:"additionalNoProxy,omitempty"`
	KubernetesUpgradePatchVersion bool   `json:"kubernetesUpgradePatchVersion,omitempty"`
	KubernetesMasterAddress       string `json:"kubernetesMasterAddress,omitempty"`
	ApiServiceAddress             string `json:"apiServiceAddress,omitempty"`
	Insecure                      bool   `json:"insecure,omitempty"`
	KubeadmTokenCAHash            string `json:"kubeadmTokenCAHash,omitempty"`
	KubernetesVersion             string `json:"kubernetesVersion,omitempty"`
	ControlPlane                  bool   `json:"controlPlane,omitempty"`
	CertKey                       string `json:"certKey,omitempty"`
	Task                          string `json:"task,omitempty"`
	DockerRegistryIP              string `json:"dockerRegistryIP,omitempty"`
	KotsadmHostname               string `json:"kotsadmHostname,omitempty"`
	KotsadmUIBindPort             string `json:"kotsadmUIBindPort,omitempty"`
	PodCIDR                       string `json:"podCIDR,omitempty"`
	RegistryPublishPort           string `json:"registryPublishPort,omitempty"`
	KotsadmApplicationNamepsaces  string `json:"kotsadmApplicationNamepsaces,omitempty"`
	VeleroNamespace               string `json:"veleroNamespace,omitempty"`
	VeleroLocalBucket             string `json:"veleroLocalBucket,omitempty"`
	VeleroDisableCLI              bool   `json:"veleroDisableCLI,omitempty"`
	VeleroDisableRestic           bool   `json:"veleroDisableRestic,omitempty"`
	KotsadmAlpha                  string `json:"kotsadmAlpha,omitempty"`
	MinioNamespace                string `json:"minioNamespace,omitempty"`
	OpenEBSNamespace              string `json:"openEBSNamespace,omitempty"`
	OpenEBSLocalPV                string `json:"openEBSLocalPV,omitempty"`
	OpenEBSLocalPVStorageClass    string `json:"openEBSLocalPVStorageClass,omitempty"`
}

type Kubernetes struct {
	Version     string `json:"version"`
	ServiceCIDR string `json:"serviceCIDR,omitempty"`
}

type Docker struct {
	Version                    string `json:"version"`
	BypassStorageDriverWarning bool   `json:"bypassStorageDriverWarning,omitempty"`
	HardFailOnLoopback         bool   `json:"hardFailOnLoopBack,omitempty"`
	NoCEOnEE                   bool   `json:"noCEOnEE,omitempty"`
}

type Weave struct {
	Version        string `json:"version"`
	EncryptNetwork bool   `json:"encryptNetwork,omitempty"`
	IPAllocRange   string `json:"IPAllocRange,omitempty"`
}

type Contour struct {
	Version string `json:"version"`
}

type Rook struct {
	Version          string `json:"version"`
	StorageClass     string `json:"storageClass,omitempty"`
	CephPoolReplicas int    `json:"cephPoolReplicas,omitempty"`
}

type Registry struct {
	Version string `json:"version"`
}

type Prometheus struct {
	Version string `json:"version"`
}
type Fluentd struct {
	Version  string `json:"version"`
	EfkStack bool   `json:"efkStack,omitempty"`
}

type Kotsadm struct {
	Version         string `json:"version"`
	ApplicationSlug string `json:"applicationSlug,omitempty"`
	UiBindPort      int    `json:"uiBindPort,omitempty"`
}

type Velero struct {
	Version    string `json:"version"`
	Namespace  string `json:"namespace,omitempty"`
	InstallCLI bool   `json:"installCLI,omitempty"`
	UseRestic  bool   `json:"useREstic,omitempty"`
}

// InstallerStatus defines the observed state of Installer
type InstallerStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
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
