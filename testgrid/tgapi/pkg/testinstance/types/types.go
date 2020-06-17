package types

import "time"

type TestInstance struct {
	ID         string     `json:"id"`
	RefID      string     `json:"refId"`
	EnqueuedAt *time.Time `json:"enqueuedAt"`
	DequeuedAt *time.Time `json:"dequeuedAt"`
	StartedAt  *time.Time `json:"startedAt"`
	FinishedAt *time.Time `json:"finishedAt"`
	IsSuccess  bool       `json:"isSuccess"`
	KurlYAML   string     `json:"kurlYaml"`
	KurlURL    string     `json:"kurlURL"`
	OSName     string     `json:"osName"`
	OSVersion  string     `json:"osVersion"`
	OSImage    string     `json:"osImage"`
}
