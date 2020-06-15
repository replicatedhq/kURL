package handlers

import (
	"net/http"
)

type ConfigResponse struct {
}

func WebConfig(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "content-type, origin, accept, authorization")

	if r.Method == "OPTIONS" {
		w.WriteHeader(200)
		return
	}

	configResponse := ConfigResponse{}

	JSON(w, 200, configResponse)
}
