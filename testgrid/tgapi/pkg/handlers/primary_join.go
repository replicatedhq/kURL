package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type JoinPrimaryRequest struct {
	PrimaryJoin   string `json:"primaryJoin"`
	SecondaryJoin string `json:"secondaryJoin"`
}

type JoinPrimaryResponse struct {
	PrimaryJoin   string `json:"primaryJoin"`
	SecondaryJoin string `json:"secondaryJoin"`
}

func AddNodeJoinCommand(w http.ResponseWriter, r *http.Request) {
	JoinPrimaryRequest := JoinPrimaryRequest{}
	if err := json.NewDecoder(r.Body).Decode(&JoinPrimaryRequest); err != nil {
		logger.Error(err)
		JSON(w, 400, nil)
		return
	}

	instanceID := mux.Vars(r)["instanceId"]

	if err := testinstance.AddNodeJoinCommand(instanceID, JoinPrimaryRequest.PrimaryJoin, JoinPrimaryRequest.SecondaryJoin); err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	JSON(w, 200, nil)
}

func GetNodeJoinCommand(w http.ResponseWriter, r *http.Request) {
	instanceID := mux.Vars(r)["instanceId"]

	primaryJoin, secondaryJoin, err := testinstance.GetNodeJoinCommand(instanceID)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, err)
		return
	}
	JoinPrimaryResponse := JoinPrimaryResponse{}
	JoinPrimaryResponse.PrimaryJoin = primaryJoin
	JoinPrimaryResponse.SecondaryJoin = secondaryJoin
	JSON(w, 200, JoinPrimaryResponse)
}
