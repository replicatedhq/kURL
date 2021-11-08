package types

import "time"

type TestInstance struct {
	ID            string     `json:"id"`
	RefID         string     `json:"refId"`
	EnqueuedAt    *time.Time `json:"enqueuedAt"`
	DequeuedAt    *time.Time `json:"dequeuedAt"`
	StartedAt     *time.Time `json:"startedAt"`
	FinishedAt    *time.Time `json:"finishedAt"`
	IsSuccess     bool       `json:"isSuccess"`
	FailureReason string     `json:"failureReason"`
	IsUnsupported bool       `json:"isUnsupported"`

	KurlYAML string `json:"kurlYaml"`
	KurlURL  string `json:"kurlUrl"`

	UpgradeYAML string `json:"upgradeYaml"`
	UpgradeURL  string `json:"upgradeUrl"`

	SupportbundleYAML string `json:"supportbundleYaml"`
	PostInstallScript string `json:"postInstallScript"`
	PostUpgradeScript string `json:"postUpgradeScript"`

	Output string `json:"-"`

	OSName    string `json:"osName"`
	OSVersion string `json:"osVersion"`
	OSImage   string `json:"-"`
	OSPreInit string `json:"-"`
}
