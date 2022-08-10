package types

import "time"

type TestInstance struct {
	ID            string     `json:"id"`
	RefID         string     `json:"refId"`
	TestID        string     `json:"testId"`
	TestName      string     `json:"testName"`
	EnqueuedAt    *time.Time `json:"enqueuedAt"`
	DequeuedAt    *time.Time `json:"dequeuedAt"`
	StartedAt     *time.Time `json:"startedAt"`
	FinishedAt    *time.Time `json:"finishedAt"`
	IsSuccess     bool       `json:"isSuccess"`
	FailureReason string     `json:"failureReason"`
	IsUnsupported bool       `json:"isUnsupported"`
	IsSkipped     bool       `json:"isSkipped"`

	KurlYAML  string `json:"kurlYaml"`
	KurlURL   string `json:"kurlUrl"`
	KurlFlags string `json:"kurlFlags"`

	UpgradeYAML string `json:"upgradeYaml"`
	UpgradeURL  string `json:"upgradeUrl"`

	NumPrimaryNodes   int    `json:"numPrimaryNodes"`
	NumSecondaryNodes int    `json:"numSecondaryNodes"`
	Memory            string `json:"memory"`
	CPU               string `json:"cpu"`

	SupportbundleYAML string `json:"supportbundleYaml"`
	PostInstallScript string `json:"postInstallScript"`
	PostUpgradeScript string `json:"postUpgradeScript"`

	Output string `json:"-"`

	OSName    string `json:"osName"`
	OSVersion string `json:"osVersion"`
	OSImage   string `json:"-"`
	OSPreInit string `json:"-"`
}
