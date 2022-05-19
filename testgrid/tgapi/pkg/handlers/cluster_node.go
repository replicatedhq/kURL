package handlers

import (
	"encoding/json"
	"io/ioutil"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type ClusterNodeRequest struct {
	NodeId   string `json:"nodeId"`
	NodeType string `json:"nodeType"`
	Status   string `json:"status"`
}

type StatusUpdateRequest struct {
	Status string `json:"status"`
}

type GetNodeLogsResponse struct {
	Logs string `json:"logs"`
}

func AddClusterNode(w http.ResponseWriter, r *http.Request) {
	instanceID := mux.Vars(r)["instanceId"]
	clusterNodeRequest := ClusterNodeRequest{}
	if err := json.NewDecoder(r.Body).Decode(&clusterNodeRequest); err != nil {
		logger.Error(err)
		JSON(w, 400, nil)
		return
	}

	if err := testinstance.AddClusterNode(instanceID, clusterNodeRequest.NodeId, clusterNodeRequest.NodeType, clusterNodeRequest.Status); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	JSON(w, 200, nil)
}

func UpdateNodeStatus(w http.ResponseWriter, r *http.Request) {
	nodeID := mux.Vars(r)["nodeId"]
	statusUpdateRequest := StatusUpdateRequest{}
	if err := json.NewDecoder(r.Body).Decode(&statusUpdateRequest); err != nil {
		logger.Error(err)
		JSON(w, 400, nil)
		return
	}
	if err := testinstance.UpdateNodeStatus(nodeID, statusUpdateRequest.Status); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	JSON(w, 200, nil)
}

func NodeLogs(w http.ResponseWriter, r *http.Request) {
	logs, err := ioutil.ReadAll(r.Body)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}
	nodeID := mux.Vars(r)["nodeId"]
	if err := testinstance.NodeLogs(nodeID, logs); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}
}

func GetNodeLogs(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "content-type, origin, accept, authorization")

	nodeID := mux.Vars(r)["nodeId"]
	logs, err := testinstance.GetNodeLogs(nodeID)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}
	getNodeLogsResponse := GetNodeLogsResponse{}
	getNodeLogsResponse.Logs = logs
	JSON(w, 200, getNodeLogsResponse)
}
