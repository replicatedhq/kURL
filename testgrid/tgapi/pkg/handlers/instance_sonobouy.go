package handlers

import (
	"bufio"
	"bytes"
	"io/ioutil"
	"net/http"
	"strings"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
	"go.uber.org/zap"
)

func InstanceSonobuoyResults(w http.ResponseWriter, r *http.Request) {
	body, err := ioutil.ReadAll(r.Body)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	instanceID := mux.Vars(r)["instanceId"]

	logger.Debug("instanceSonobuoyResults",
		zap.String("instanceId", instanceID))

	if err := testinstance.SetInstanceSonobuoyResults(instanceID, body); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	isSuccess := false
	scanner := bufio.NewScanner(bytes.NewReader(body))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "Status:") {
			isSuccess = strings.HasSuffix(line, "passed")
		}
	}

	if err := testinstance.SetInstanceSuccess(instanceID, isSuccess); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	JSON(w, 200, nil)
}
