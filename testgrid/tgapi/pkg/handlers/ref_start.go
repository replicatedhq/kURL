package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testrun"
	"go.uber.org/zap"
)

type StartRefRequest struct {
	Overwrite bool              `json:"overwrite"`
	Instances []PlannedInstance `json:"instances"`
}

type StartRefResponse struct {
	Success bool `json:"success"`
}

type PlannedInstance struct {
	ID string

	KurlYAML string
	KurlURL  string

	UpgradeYAML string
	UpgradeURL  string

	SupportbundleYAML string

	PostInstallScript string
	PostUpgradeScript string

	OperatingSystemName    string
	OperatingSystemVersion string
	OperatingSystemImage   string
	OperatingSystemPreInit string

	IsUnsupported bool
}

func StartRef(w http.ResponseWriter, r *http.Request) {
	startRefRequest := StartRefRequest{}
	if err := json.NewDecoder(r.Body).Decode(&startRefRequest); err != nil {
		logger.Error(err)
		JSON(w, 500, StartRefResponse{})
		return
	}

	refID := mux.Vars(r)["refId"]

	logger.Debug("refStart",
		zap.String("ref", refID))

	existingTestRun, err := testrun.TryGet(refID)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, StartRefResponse{})
		return
	}

	if existingTestRun != nil {
		if !startRefRequest.Overwrite {
			JSON(w, 419, StartRefResponse{})
			return
		}

		if err := testrun.Delete(refID); err != nil {
			logger.Error(err)
			JSON(w, 500, StartRefResponse{})
			return
		}
	}

	if err := testrun.Create(refID); err != nil {
		logger.Error(err)
		JSON(w, 500, StartRefResponse{})
		return
	}

	for _, plannedInstance := range startRefRequest.Instances {
		err := testinstance.Create(
			plannedInstance.ID,
			refID,
			plannedInstance.KurlYAML,
			plannedInstance.KurlURL,
			plannedInstance.UpgradeYAML,
			plannedInstance.UpgradeURL,
			plannedInstance.SupportbundleYAML,
			plannedInstance.PostInstallScript,
			plannedInstance.PostUpgradeScript,
			plannedInstance.OperatingSystemName,
			plannedInstance.OperatingSystemVersion,
			plannedInstance.OperatingSystemImage,
			plannedInstance.OperatingSystemPreInit,
		)
		if err != nil {
			logger.Error(err)
			JSON(w, 500, StartRefResponse{})
			return
		}
		if plannedInstance.IsUnsupported {
			err := testinstance.SetInstanceUnsupported(plannedInstance.ID)
			if err != nil {
				logger.Error(err)
				JSON(w, 500, StartRefResponse{})
				return
			}
		}
	}

	JSON(w, 200, StartRefResponse{Success: true})
}
