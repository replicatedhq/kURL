package handlers

import (
	"fmt"
	"net/http"

	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/persistence"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type HealthzResponse struct {
	IsAlive bool `json:"is_alive"`
}

func Healthz(w http.ResponseWriter, r *http.Request) {
	healthzResponse := HealthzResponse{
		IsAlive: true,
	}

	pending, running, timedOut, err := testinstance.GetTestStats()
	if err != nil {
		fmt.Printf("error getting test stats: %s", err)
		return // being unable to get test stats indicates unhealthiness
	}

	go func(pending, running, timedOut int64) {
		persistence.MaybeSendStatsdGauge("pending", float64(pending), nil, 1.0)         // the number of pending test runs
		persistence.MaybeSendStatsdGauge("running_3h", float64(running), nil, 1.0)      // the number of test runs that have been running for <3h
		persistence.MaybeSendStatsdGauge("running_3h_24h", float64(timedOut), nil, 1.0) // the number of test runs that have been running for >3h and <24h (and that can be assumed to have timed out)
	}(pending, running, timedOut)

	JSON(w, 200, healthzResponse)
}
