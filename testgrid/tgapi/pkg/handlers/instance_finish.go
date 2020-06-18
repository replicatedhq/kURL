package handlers

import (
	"net/http"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
	"go.uber.org/zap"
)

func FinishInstance(w http.ResponseWriter, r *http.Request) {
	instanceID := mux.Vars(r)["instanceId"]

	logger.Debug("finishInstance",
		zap.String("instanceId", instanceID))

	if err := testinstance.Finish(instanceID); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	JSON(w, 200, nil)
}
