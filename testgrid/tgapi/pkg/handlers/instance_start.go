package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
	"go.uber.org/zap"
)

type StartInstanceRequest struct {
	OSName    string `json:"osName"`
	OSVersion string `json:"osVersion"`
	OSImage   string `json:"osImage"`

	Memory string `json:"memory"`
	CPU    string `json:"cpu"`

	KurlRef  string `json:"kurlRef"`
	KurlSpec string `json:"kurlSpec"`
	KurlURL  string `json:"kurlUrl"`
}

func StartInstance(w http.ResponseWriter, r *http.Request) {
	startInstanceRequest := StartInstanceRequest{}
	if err := json.NewDecoder(r.Body).Decode(&startInstanceRequest); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	instanceID := mux.Vars(r)["instanceId"]

	logger.Debug("startInstance",
		zap.String("instanceId", instanceID))

	if err := testinstance.Start(instanceID); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	JSON(w, 200, nil)
}
