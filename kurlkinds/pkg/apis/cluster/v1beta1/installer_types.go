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
	Contour         Contour         `json:"contour,omitempty"`
	Rook            Rook            `json:"rook,omitempty"`
	Registry        Registry        `json:"registry,omitempty"`
	Prometheus      Prometheus      `json:"prometheus,omitempty"`
	Fluentd         Fluentd         `json:"fluentd,omitempty"`
	Kotsadm         Kotsadm         `json:"kotsadm,omitempty"`
	Velero          Velero          `json:"velero,omitempty"`
	Minio           Minio           `json:"minio,omitempty"`
	OpenEBS         OpenEBS         `json:"openEBS,omitempty"`
	Kurl            Kurl            `json:"kurl,omitempty"`
	SelinuxConfig   SelinuxConfig   `json:"selinuxConfig,omitempty"`
	IptablesConfig  IptablesConfig  `json:"iptablesConfig,omitempty"`
	FirewalldConfig FirewalldConfig `json:"firewalldConfig,omitempty"`
}

type Contour struct {
	Version string `json:"version"`
}

type Docker struct {
	AdditionalNoProxy          string `json:"additionalNoProxy,omitempty"`
	BypassStorageDriverWarning bool   `json:"bypassStorageDriverWarning,omitempty"`
	DockerRegistryIP           string `json:"dockerRegistryIP,omitempty"`
	HardFailOnLoopback         bool   `json:"hardFailOnLoopback,omitempty"`
	NoCEOnEE                   bool   `json:"noCEOnEE,omitempty"`
	NoDocker                   bool   `json:"noDocker,omitempty"`
	Version                    string `json:"version"`
	DaemonConfig               string `json:"daemonConfig,omitempty"`
}

type Fluentd struct {
	FullEFKStack bool   `json:"fullEFKStack,omitempty"`
	Version      string `json:"version"`
}

type Kotsadm struct {
	ApplicationNamespace string `json:"applicationNamespace,omitempty"`
	ApplicationSlug      string `json:"applicationSlug,omitempty"`
	Hostname             string `json:"hostname,omitempty"`
	UiBindPort           int    `json:"uiBindPort,omitempty"`
	Version              string `json:"version"`
}

type Kubernetes struct {
	BootstrapToken      string `json:"bootstrapToken,omitempty"`
	BootstrapTokenTTL   string `json:"bootstrapTokenTTL,omitempty"`
	CertKey             string `json:"certKey,omitempty"`
	ControlPlane        bool   `json:"controlPlane,omitempty"`
	HACluster           bool   `json:"HACluster,omitempty"`
	KubeadmTokenCAHash  string `json:"kubeadmTokenCAHash,omitempty"`
	LoadBalancerAddress string `json:"loadBalancerAddress,omitempty"`
	MasterAddress       string `json:"masterAddress,omitempty"`
	ServiceCIDR         string `json:"serviceCIDR,omitempty"`
	ServiceCidrRange    string `json:"serviceCidrRange,omitempty"`
	Version             string `json:"version"`
}

type Kurl struct {
	Airgap                 bool   `json:"airgap,omitempty"`
	HostnameCheck          string `json:"hostnameCheck,omitempty"`
	HTTPProxy              string `json:"HTTPProxy,omitempty"`
	NoProxy                bool   `json:"noProxy,omitempty"`
	PublicAddress          string `json:"publicAddress,omitempty"`
	PrivateAddress         string `json:"privateAddress,omitempty"`
	HardFailOnFirewalld    bool   `json:"hardFailOnFirewalld,omitempty"`
	BypassFirewalldWarning bool   `json:"bypassFirewalldWarning,omitempty"`
	Task                   string `json:"task,omitempty"`
}

type Minio struct {
	Namespace string `json:"namespace,omitempty"`
	Version   string `json:"version"`
}

type OpenEBS struct {
	IsLocalPVEnabled        bool   `json:"isLocalPVEnabled,omitempty"`
	LocalPVStorageClassName string `json:"localPVStorageClassName,omitempty"`
	IsCstorEnabled          bool   `json:"isCstorEnabled,omitempty"`
	CstorStorageClassName   string `json:"cstorStorageClassName,omitempty"`
	Namespace               string `json:"namespace,omitempty"`
	Version                 string `json:"version"`
}

type Prometheus struct {
	Version string `json:"version"`
}

type Registry struct {
	publishPort int    `json:"publishPort,omitempty"`
	Version     string `json:"version"`
}

type Rook struct {
	CephReplicaCount      int    `json:"cephReplicaCount,omitempty"`
	StorageClassName      string `json:"storageClassName,omitempty"`
	Version               string `json:"version"`
	IsBlockStorageEnabled bool   `json:"isBlockStorageEnabled,omitempty"`
	BlockDeviceFilter     string `json:"blockDeviceFilter,omitempty"`
}

type Velero struct {
	DisableRestic bool   `json:"disableRestic,omitempty"`
	DisableCLI    bool   `json:"disableCLI,omitempty"`
	LocalBucket   string `json:"localBucket,omitempty"`
	Namespace     string `json:"namespace,omitempty"`
	Version       string `json:"version"`
}

type Weave struct {
	isEncryptionDisabled bool   `json:"isEncryptionDisabled,omitempty"`
	PodCIDR              string `json:"podCIDR,omitempty"`
	PodCidrRange         string `json:"podCidrRange,omitempty"`
	Version              string `json:"version"`
}

type SelinuxConfig struct {
	Selinux      string     `json:"selinux,omitempty"`
	Type         string     `json:"type,omitempty"`
	SemanageCmds [][]string `json:"semanageCmds,omitempty"`
	ChconCmds    [][]string `json:"chconCmds,omitempty"`
}

type IptablesConfig struct {
	IptablesCmds [][]string `json:"iptablesCmds,omitempty"`
}

type FirewalldConfig struct {
	Firewalld     string     `json:"firewalld,omitempty"`
	FirewalldCmds [][]string `json:"firewalldCmds,omitempty"`
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
