package types

import (
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
)

type SchedulerOptions struct {
	APIEndpoint  string
	APIToken     string
	OverwriteRef bool
	Ref          string
	Staging      bool
	Airgap       bool
	KurlVersion  string
	Spec         string
	OSSpec       string
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
	PreInit    string // a script to run before the test - for instance, to convert to oracle linux
}

type Instance struct {
	Name             string                     `json:"name" yaml:"name"`
	InstallerSpec    kurlv1beta1.InstallerSpec  `json:"installerSpec" yaml:"installerSpec"`
	UpgradeSpec      *kurlv1beta1.InstallerSpec `json:"upgradeSpec,omitempty" yaml:"upgradeSpec,omitempty"`
	Airgap           bool                       `json:"airgap,omitempty" yaml:"airgap,omitempty"`
	UnsupportedOSIDs []string                   `json:"unsupportedOSIDs,omitempty" yaml:"unsupportedOSIDs,omitempty"`
}
