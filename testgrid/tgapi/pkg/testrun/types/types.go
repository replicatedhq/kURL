package types

import "time"

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
