package types

import "time"

type TestInstance struct {
	ID         string
	RefID      string
	EnqueuedAt *time.Time
	DequeuedAt *time.Time
	StartedAt  *time.Time
	FinishedAt *time.Time
	IsSuccess  bool

	KurlYAML string
	KurlURL  string

	Output string

	OSName    string
	OSVersion string
	OSImage   string
}
