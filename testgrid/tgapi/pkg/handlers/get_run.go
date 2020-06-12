package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type GetRunResponse struct {
	Instances []InstanceResponse `json:"instances"`
	Total     int                `json:"total"`
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

	pSize := r.URL.Query().Get("pageSize")
	cPage := r.URL.Query().Get("currentPage")

	var pageSize int
	if pSize != "" {
		var err error
		pageSize, err = strconv.Atoi(pSize)
		if err != nil {
			pageSize = 20
		}
	} else {
		pageSize = 20
	}

	var currentPage int
	if cPage != "" {
		currentPage, _ = strconv.Atoi(cPage)
	}

	instances, err := testinstance.List(mux.Vars(r)["refId"], pageSize, currentPage*pageSize)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	total, err := testinstance.Total(mux.Vars(r)["refId"])
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

	JSON(w, 200, getRunResponse)
}
