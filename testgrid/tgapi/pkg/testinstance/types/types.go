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
	IsUnsupported bool       `json:"isUnsupported"`

	KurlYAML string `json:"kurlYaml"`
	KurlURL  string `json:"kurlURL"`

	Output string `json:"-"`

	OSName    string `json:"osName"`
	OSVersion string `json:"osVersion"`
	OSImage   string `json:"-"`

	TimeoutAfter string `json:"timeoutAfter"`
}
