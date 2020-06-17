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
)

func InstanceSonobuoyResults(w http.ResponseWriter, r *http.Request) {
	body, err := ioutil.ReadAll(r.Body)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	instanceId := mux.Vars(r)["instanceId"]
	if err := testinstance.SetInstanceSonobuoyResults(instanceId, body); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	/*
		Plugin: e2e
		Status: passed
		Total: 4843
		Passed: 1
		Failed: 0
		Skipped: 4842
	*/

	isSuccess := false
	scanner := bufio.NewScanner(bytes.NewReader(body))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "Status:") {
			isSuccess = strings.HasSuffix(line, "passed")
		}

	}

	if err := testinstance.SetInstanceSuccess(instanceId, isSuccess); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	JSON(w, 200, nil)
}
