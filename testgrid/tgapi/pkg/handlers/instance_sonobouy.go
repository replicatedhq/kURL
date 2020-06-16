package handlers

import (
	"fmt"
	"io/ioutil"
	"net/http"

	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
)

func InstanceSonobouyResults(w http.ResponseWriter, r *http.Request) {
	body, err := ioutil.ReadAll(r.Body)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	fmt.Printf("sonobouy results = %s\n", body)

	JSON(w, 200, nil)
}
