package handlers

import (
	"net/http"
	"time"

	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testrun"
)

type ListRunsResponse struct {
	Runs []RunResponse `json:"runs"`
}

type RunResponse struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"created_at"`
}

func ListRuns(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "content-type, origin, accept, authorization")

	if r.Method == "OPTIONS" {
		w.WriteHeader(200)
		return
	}

	testRuns, err := testrun.List()
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	runs := []RunResponse{}
	for _, testRun := range testRuns {
		run := RunResponse{
			ID:        testRun.ID,
			CreatedAt: testRun.CreatedAt,
		}

		runs = append(runs, run)
	}

	listRunsResponse := ListRunsResponse{
		Runs: runs,
	}

	JSON(w, 200, listRunsResponse)
}
