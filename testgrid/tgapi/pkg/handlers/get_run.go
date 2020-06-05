package handlers

import (
	"net/http"
	"time"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type GetRunResponse struct {
	Instances []InstanceResponse `json:"instances"`
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

	instances, err := testinstance.List(mux.Vars(r)["refId"])
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

	JSON(w, 200, getRunResponse)
}
