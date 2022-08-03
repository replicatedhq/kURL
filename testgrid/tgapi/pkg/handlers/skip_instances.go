package handlers

import (
	"log"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

func SkipInstances(w http.ResponseWriter, r *http.Request) {
	refID := mux.Vars(r)["refId"]

	err := testinstance.SkipEnqueuedByRef(refID)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		log.Printf("error skipping ref: %v", err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
