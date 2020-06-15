package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testrun"
)

type StartRefRequest struct {
	Overwrite bool              `json:"overwrite"`
	Instances []PlannedInstance `json:"instances"`
}

type PlannedInstance struct {
	ID string

	KurlYAML string
	KurlURL  string

	OperatingSystemName    string
	OperatingSystemVersion string
	OperatingSystemImage   string
}

func StartRef(w http.ResponseWriter, r *http.Request) {
	startRefRequest := StartRefRequest{}
	if err := json.NewDecoder(r.Body).Decode(&startRefRequest); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	refID := mux.Vars(r)["refId"]

	existingTestRun, err := testrun.TryGet(refID)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	if existingTestRun != nil {
		if !startRefRequest.Overwrite {
			JSON(w, 419, nil)
			return
		}

		if err := testrun.Delete(refID); err != nil {
			logger.Error(err)
			JSON(w, 500, nil)
			return
		}
	}

	if err := testrun.Create(refID); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	for _, plannedInstance := range startRefRequest.Instances {
		if err := testinstance.Create(
			plannedInstance.ID,
			refID,
			plannedInstance.KurlYAML,
			plannedInstance.KurlURL,
			plannedInstance.OperatingSystemName,
			plannedInstance.OperatingSystemVersion,
			plannedInstance.OperatingSystemImage,
		); err != nil {
			logger.Error(err)
			JSON(w, 500, nil)
			return
		}
	}

	JSON(w, 200, nil)
}
