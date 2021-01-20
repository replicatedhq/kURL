package types

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type SchedulerOptions struct {
	APIEndpoint  string
	OverwriteRef bool
	Ref          string
	Staging      bool
	LatestOnly   bool
	Spec         string
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
	IsStaging       bool                         `json:"-" yaml:"-"`
	Kubernetes      kurlv1beta1.Kubernetes       `json:"kubernetes,omitempty" yaml:"kubernetes,omitempty"`
	Docker          *kurlv1beta1.Docker          `json:"docker,omitempty" yaml:"docker,omitempty"`
	Containerd      *kurlv1beta1.Containerd      `json:"containerd,omitempty" yaml:"containerd,omitempty"`
	Weave           *kurlv1beta1.Weave           `json:"weave,omitempty" yaml:"weave,omitempty"`
	Calico          *kurlv1beta1.Calico          `json:"calico,omitempty" yaml:"calico,omitempty"`
	Contour         *kurlv1beta1.Contour         `json:"contour,omitempty" yaml:"contour,omitempty"`
	Rook            *kurlv1beta1.Rook            `json:"rook,omitempty" yaml:"rook,omitempty"`
	Registry        *kurlv1beta1.Registry        `json:"registry,omitempty" yaml:"registry,omitempty"`
	Prometheus      *kurlv1beta1.Prometheus      `json:"prometheus,omitempty" yaml:"prometheus,omitempty"`
	Fluentd         *kurlv1beta1.Fluentd         `json:"fluentd,omitempty" yaml:"fluentd,omitempty"`
	Kotsadm         *kurlv1beta1.Kotsadm         `json:"kotsadm,omitempty" yaml:"kotsadm,omitempty"`
	Velero          *kurlv1beta1.Velero          `json:"velero,omitempty" yaml:"velero,omitempty"`
	Minio           *kurlv1beta1.Minio           `json:"minio,omitempty" yaml:"minio,omitempty"`
	OpenEBS         *kurlv1beta1.OpenEBS         `json:"openebs,omitempty" yaml:"openebs,omitempty"`
	Kurl            *kurlv1beta1.Kurl            `json:"kurl,omitempty" yaml:"kurl,omitempty"`
	SelinuxConfig   *kurlv1beta1.SelinuxConfig   `json:"selinuxConfig,omitempty" yaml:"selinuxConfig,omitempty"`
	IptablesConfig  *kurlv1beta1.IptablesConfig  `json:"iptablesConfig,omitempty" yaml:"iptablesConfig,omitempty"`
	FirewalldConfig *kurlv1beta1.FirewalldConfig `json:"firewalldConfig,omitempty" yaml:"firewalldConfig,omitempty"`
	Ekco            *kurlv1beta1.Ekco            `json:"ekco,omitempty" json:"ekco,omitempty"`
	Collectd        *kurlv1beta1.Collectd        `json:"collectd,omitempty" yaml:"collectd,omitempty"`
	CertManager     *kurlv1beta1.CertManager     `json:"certManager,omitempty" yaml:"certManager,omitempty"`
	MetricsServer   *kurlv1beta1.MetricsServer   `json:"metricsServer,omitempty" yaml:"metricsServer,omitempty"`
}
