package handlers

import (
	"fmt"
	"io/ioutil"
	"net/http"

	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
)

func InstanceBundle(w http.ResponseWriter, r *http.Request) {
	bundle, err := ioutil.ReadAll(r.Body)
	if err != nil {
		logger.Error(err)
		JSON(w, 500, nil)
		return
	}

	fmt.Printf("bundle size = %d\n", len(bundle))

	JSON(w, 200, nil)
}
