package handlers

import (
	"net/http"
)

type HealthzResponse struct {
	IsAlive bool `json:"is_alive"`
}

func Healthz(w http.ResponseWriter, r *http.Request) {
	healthzResponse := HealthzResponse{
		IsAlive: true,
	}

	JSON(w, 200, healthzResponse)
}
