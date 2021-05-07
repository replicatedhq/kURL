package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance/types"
)

type GetRunRequest struct {
	PageSize    int               `json:"pageSize"`
	CurrentPage int               `json:"currentPage"`
	Addons      map[string]string `json:"addons"`
}

type GetRunResponse struct {
	Instances    []types.TestInstance `json:"instances"`
	Total        int                  `json:"total"`
	LastStart    *time.Time           `json:"last_start"`
	LastResponse *time.Time           `json:"last_response"`
	SuccessCount int64                `json:"success_count"` // success_count plus failure_count will not always equal total due to unsupported instances
	FailureCount int64                `json:"failure_count"`
}

func GetRun(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "content-type, origin, accept, authorization")

	if r.Method == "OPTIONS" {
		w.WriteHeader(200)
		return
	}

	getRunRequest := GetRunRequest{}
	if err := json.NewDecoder(r.Body).Decode(&getRunRequest); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}
	if getRunRequest.PageSize == 0 {
		getRunRequest.PageSize = 500
	}

	instances, err := testinstance.List(mux.Vars(r)["refId"], getRunRequest.PageSize, getRunRequest.CurrentPage*getRunRequest.PageSize, getRunRequest.Addons)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	total, err := testinstance.Total(mux.Vars(r)["refId"], getRunRequest.Addons)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	getRunResponse := GetRunResponse{}

	getRunResponse.Instances = instances
	getRunResponse.Total = total

	// calculate the last completed test run and the number of successes/failures
	for _, instance := range instances {
		if instance.FinishedAt != nil {
			if getRunResponse.LastResponse == nil || getRunResponse.LastResponse.Before(*instance.FinishedAt) {
				getRunResponse.LastResponse = instance.FinishedAt
			}
		}
		if instance.StartedAt != nil {
			if getRunResponse.LastStart == nil || getRunResponse.LastStart.Before(*instance.StartedAt) {
				getRunResponse.LastStart = instance.StartedAt
			}
		}
		if !instance.IsUnsupported && instance.FinishedAt != nil {
			if instance.IsSuccess {
				getRunResponse.SuccessCount++
			} else {
				getRunResponse.FailureCount++
			}
		}
	}

	JSON(w, 200, getRunResponse)
}
