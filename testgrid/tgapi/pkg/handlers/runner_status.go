package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/persistence"
	"go.uber.org/zap"
)

type RunnerStatusRequest struct {
	FreeCPU      float64 `json:"freeCPU"`
	FreeRAM      float64 `json:"freeRAM"`
	RunningTests float64 `json:"runningTests"`
	Hostname     string  `json:"hostname"`
}

func RunnerStatus(w http.ResponseWriter, r *http.Request) {
	runnerStatusRequest := RunnerStatusRequest{}
	if err := json.NewDecoder(r.Body).Decode(&runnerStatusRequest); err != nil {
		logger.Error(err)
		JSON(w, 400, nil)
		return
	}

	logger.Debug("testRunner",
		zap.String("runnerID", runnerStatusRequest.Hostname))

	persistence.MaybeSendStatsdGauge("testgrid_runner_free_cpu", runnerStatusRequest.FreeCPU, []string{runnerStatusRequest.Hostname}, 1.0)
	persistence.MaybeSendStatsdGauge("testgrid_runner_free_ram", runnerStatusRequest.FreeRAM, []string{runnerStatusRequest.Hostname}, 1.0)
	persistence.MaybeSendStatsdGauge("testgrid_runner_active_tests", runnerStatusRequest.RunningTests, []string{runnerStatusRequest.Hostname}, 1.0)

	JSON(w, 200, nil)
}
