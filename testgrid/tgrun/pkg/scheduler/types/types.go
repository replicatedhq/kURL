package types

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type SchedulerOptions struct {
	APIEndpoint  string
	OverwriteRef bool
	Ref          string
}

type TestRun struct {
	InstanceID string

	VMImageURI string

	OSName    string
	OSVersion string

	KurlSpec string
	KurlSHA  string
}

type OperatingSystemImage struct {
	ID         string
	Name       string
	Version    string
	VMImageURI string
}

type Instance struct {
	InstallerSpec    InstallerSpec
	UnsupportedOSIDs []string
}

type Installer struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec InstallerSpec `json:"spec,omitempty"`
}

type InstallerSpec struct {
	IsStaging       bool                         `json:"-"`
	Kubernetes      kurlv1beta1.Kubernetes       `json:"kubernetes,omitempty"`
	Docker          *kurlv1beta1.Docker          `json:"docker,omitempty"`
	Containerd      *kurlv1beta1.Containerd      `json:"containerd,omitempty"`
	Weave           *kurlv1beta1.Weave           `json:"weave,omitempty"`
	Calico          *kurlv1beta1.Calico          `json:"calico,omitempty"`
	Contour         *kurlv1beta1.Contour         `json:"contour,omitempty"`
	Rook            *kurlv1beta1.Rook            `json:"rook,omitempty"`
	Registry        *kurlv1beta1.Registry        `json:"registry,omitempty"`
	Prometheus      *kurlv1beta1.Prometheus      `json:"prometheus,omitempty"`
	Fluentd         *kurlv1beta1.Fluentd         `json:"fluentd,omitempty"`
	Kotsadm         *kurlv1beta1.Kotsadm         `json:"kotsadm,omitempty"`
	Velero          *kurlv1beta1.Velero          `json:"velero,omitempty"`
	Minio           *kurlv1beta1.Minio           `json:"minio,omitempty"`
	OpenEBS         *kurlv1beta1.OpenEBS         `json:"openebs,omitempty"`
	Kurl            *kurlv1beta1.Kurl            `json:"kurl,omitempty"`
	SelinuxConfig   *kurlv1beta1.SelinuxConfig   `json:"selinuxConfig,omitempty"`
	IptablesConfig  *kurlv1beta1.IptablesConfig  `json:"iptablesConfig,omitempty"`
	FirewalldConfig *kurlv1beta1.FirewalldConfig `json:"firewalldConfig,omitempty"`
	Ekco            *kurlv1beta1.Ekco            `json:"ekco,omitempty"`
}
