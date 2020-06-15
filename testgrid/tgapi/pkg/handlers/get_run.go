package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type GetRunRequest struct {
	PageSize    int               `json:"pageSize"`
	CurrentPage int               `json:"currentPage"`
	Addons      map[string]string `json:"addons"`
}

type GetRunResponse struct {
	Instances []InstanceResponse `json:"instances"`
	Total     int                `json:"total"`
	Addons    []string           `json:"addons"`
}

type InstanceResponse struct {
	ID         string     `json:"id"`
	OSName     string     `json:"osName"`
	OSVersion  string     `json:"osVersion"`
	KurlYAML   string     `json:"kurlYaml"`
	KurlURL    string     `json:"kurlURL"`
	StartedAt  *time.Time `json:"startedAt"`
	FinishedAt *time.Time `json:"finishedAt"`
	IsSuccess  bool       `json:"isSuccess"`
}

func GetRun(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "content-type, origin, accept, authorization")

	if r.Method == "OPTIONS" {
		w.WriteHeader(200)
		return
	}

	getRunRequest := GetRunRequest{}
	if err := json.NewDecoder(r.Body).Decode(&getRunRequest); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}
	if getRunRequest.PageSize == 0 {
		getRunRequest.PageSize = 20
	}

	instances, err := testinstance.List(mux.Vars(r)["refId"], getRunRequest.PageSize, getRunRequest.CurrentPage*getRunRequest.PageSize, getRunRequest.Addons)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	total, err := testinstance.Total(mux.Vars(r)["refId"], getRunRequest.Addons)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	uniqueAddons, err := testinstance.GetUniqueAddons(mux.Vars(r)["refId"])
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	getRunResponse := GetRunResponse{}

	instanceResponses := []InstanceResponse{}
	for _, instance := range instances {
		instanceResponse := InstanceResponse{
			ID:         instance.ID,
			OSName:     instance.OSName,
			OSVersion:  instance.OSVersion,
			KurlYAML:   instance.KurlYAML,
			KurlURL:    instance.KurlURL,
			StartedAt:  instance.StartedAt,
			FinishedAt: instance.FinishedAt,
			IsSuccess:  instance.IsSuccess,
		}

		instanceResponses = append(instanceResponses, instanceResponse)
	}

	getRunResponse.Instances = instanceResponses
	getRunResponse.Total = total
	getRunResponse.Addons = uniqueAddons

	JSON(w, 200, getRunResponse)
}
