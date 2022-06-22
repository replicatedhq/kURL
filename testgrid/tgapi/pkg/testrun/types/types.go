package types

import (
	"time"
)

type TestRun struct {
	ID           string     `json:"id"`
	CreatedAt    time.Time  `json:"created_at"`
	LastStart    *time.Time `json:"last_start"`
	LastResponse *time.Time `json:"last_response"`
	SuccessCount int64      `json:"success_count"` // success_count plus failure_count will not always equal total due to unsupported instances
	FailureCount int64      `json:"failure_count"`
	TotalRuns    int64      `json:"total_runs"`
	PendingRuns  int64      `json:"pending_runs"`
}

type TestRunInstance struct {
	ID                string     `json:"id" yaml:"id"`
	TestName          string     `json:"testName" yaml:"testName"`
	NumPrimaryNodes   *int       `json:"numPrimaryNodes" yaml:"numPrimaryNodes"`
	NumSecondaryNodes *int       `json:"numSecondaryNodes" yaml:"numSecondaryNodes"`
	Memory            *int       `json:"memory" yaml:"memory"`
	CPU               *int       `json:"cpu" yaml:"cpu"`
	RefID             string     `json:"refId" yaml:"refId"`
	KurlYAML          string     `json:"kurlYAML" yaml:"kurlYAML"`
	KurlURL           string     `json:"kurlURL" yaml:"kurlURL"`
	KurlFlags         string     `json:"kurlFlags" yaml:"kurlFlags"`
	UpgradeYAML       string     `json:"upgradeYAML" yaml:"upgradeYAML"`
	UpgradeURL        string     `json:"upgradeURL" yaml:"upgradeURL"`
	SupportbundleYAML string     `json:"supportbundleYAML" yaml:"supportbundleYAML"`
	PostInstallScript string     `json:"postInstallScript" yaml:"postInstallScript"`
	PostUpgradeScript string     `json:"postUpgradeScript" yaml:"postUpgradeScript"`
	OSName            string     `json:"osName" yaml:"osName"`
	OSVersion         string     `json:"osVersion" yaml:"osVersion"`
	OSImage           string     `json:"osImage" yaml:"osImage"`
	OSPreInit         string     `json:"osPreInit" yaml:"osPreInit"`
	StartedAt         *time.Time `json:"started_at" yaml:"started_at"`
	RunningAt         *time.Time `json:"running_at" yaml:"running_at"`
	FinishedAt        *time.Time `json:"finished_at" yaml:"finished_at"`
	DequeuedAt        *time.Time `json:"dequeued_at" yaml:"dequeued_at"`
	IsSuccess         *bool      `json:"is_success" yaml:"is_success"`
	EnqueuedAt        *time.Time `json:"enqueuedAt" yaml:"enqueuedAt"`
	FailureReason     string     `json:"failure_reason" yaml:"failure_reason"`
	IsUnsupported     *bool      `json:"is_unsupported" yaml:"is_unsupported"`
}
