package handlers

import (
	"net/http"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type GetRunAddonsResponse struct {
	Addons []string `json:"addons"`
}

func GetRunAddons(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "content-type, origin, accept, authorization")

	if r.Method == "OPTIONS" {
		w.WriteHeader(200)
		return
	}

	uniqueAddons, err := testinstance.GetUniqueAddons(mux.Vars(r)["refId"])
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	getRunAddonsResponse := GetRunAddonsResponse{}
	getRunAddonsResponse.Addons = uniqueAddons

	JSON(w, 200, getRunAddonsResponse)
}
