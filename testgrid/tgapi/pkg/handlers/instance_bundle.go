package handlers

import (
	"io/ioutil"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"go.uber.org/zap"
)

func InstanceBundle(w http.ResponseWriter, r *http.Request) {
	bundle, err := ioutil.ReadAll(r.Body)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	instanceID := mux.Vars(r)["instanceId"]

	logger.Debug("instanceBundle",
		zap.String("instanceId", instanceID),
		zap.Int("bundleSize", len(bundle)))

	JSON(w, 200, nil)
}
