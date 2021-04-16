package types

import "time"

type TestInstance struct {
	ID            string     `json:"id"`
	RefID         string     `json:"refID"`
	EnqueuedAt    *time.Time `json:"enqueuedAt"`
	DequeuedAt    *time.Time `json:"dequeuedAt"`
	StartedAt     *time.Time `json:"startedAt"`
	FinishedAt    *time.Time `json:"finishedAt"`
	IsSuccess     bool       `json:"isSuccess"`
	Failure       string     `json:"failure"`
	IsUnsupported bool       `json:"isUnsupported"`

	KurlYAML string `json:"kurlYaml"`
	KurlURL  string `json:"kurlURL"`

	UpgradeYAML string `json:"upgradeYaml"`
	UpgradeURL  string `json:"upgradeURL"`

	Output string `json:"-"`

	OSName    string `json:"osName"`
	OSVersion string `json:"osVersion"`
	OSImage   string `json:"-"`
	OSPreInit string `json:"-"`
}
