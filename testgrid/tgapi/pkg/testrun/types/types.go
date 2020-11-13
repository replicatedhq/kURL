package types

import "time"

type TestRun struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"created_at"`
}
