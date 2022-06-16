package handlers

import (
	"fmt"
	"net/http"

	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type HealthzResponse struct {
	IsAlive bool `json:"is_alive"`
}

func Healthz(w http.ResponseWriter, r *http.Request) {
	healthzResponse := HealthzResponse{
		IsAlive: true,
	}

	err := testinstance.Healthz()
	if err != nil {
		fmt.Printf("error connecting to the db: %s", err)
		JSON(w, 500, healthzResponse)
		return // being unable to connect to the db indicates unhealthiness
	}

	JSON(w, 200, healthzResponse)
}
