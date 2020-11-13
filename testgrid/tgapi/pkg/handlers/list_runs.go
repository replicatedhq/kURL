package handlers

import (
	"net/http"
	"strconv"

	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testrun"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testrun/types"
)

type ListRunsResponse struct {
	Runs  []types.TestRun `json:"runs"`
	Total int             `json:"total"`
}

func ListRuns(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "content-type, origin, accept, authorization")

	if r.Method == "OPTIONS" {
		w.WriteHeader(200)
		return
	}

	pSize := r.URL.Query().Get("pageSize")
	cPage := r.URL.Query().Get("currentPage")
	searchRef := r.URL.Query().Get("searchRef")

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

	testRuns, err := testrun.List(pageSize, currentPage*pageSize, searchRef)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	total, err := testrun.Total(searchRef)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	listRunsResponse := ListRunsResponse{
		Runs:  testRuns,
		Total: total,
	}

	JSON(w, 200, listRunsResponse)
}
