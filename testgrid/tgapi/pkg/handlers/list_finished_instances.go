package handlers

import (
	"net/http"
	"time"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance/types"
)

type ListFinishedInstancesResponse struct {
	Instances []types.TestInstance `json:"instances"`
}

func ListFinishedInstances(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "content-type, origin, accept, authorization")

	if r.Method == "OPTIONS" {
		w.WriteHeader(200)
		return
	}

	duration := 90 * time.Minute

	if durationStr := r.URL.Query().Get("duration"); durationStr != "" {
		d, err := time.ParseDuration(durationStr)
		if err != nil {
			err := errors.Wrap(err, "failed to parse duration")
			logger.Error(err)
			JSON(w, 400, map[string]string{"error": err.Error()})
			return
		}
		duration = d
	}

	testInstances, err := testinstance.ListFinishedWithinDuration(duration)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	response := ListFinishedInstancesResponse{
		Instances: testInstances,
	}

	JSON(w, 200, response)
}
