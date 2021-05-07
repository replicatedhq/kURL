package handlers

import (
	"database/sql"
	"fmt"
	"net/http"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type DequeueInstanceResponse struct {
	ID string `json:"id"`

	OperatingSystemName    string `json:"operatingSystemName"`
	OperatingSystemVersion string `json:"operatingSystemVersion"`
	OperatingSystemImage   string `json:"operatingSystemImage"`
	OperatingSystemPreInit string `json:"operatingSystemPreInit"`

	KurlYAML   string `json:"kurlYaml"`
	KurlURL    string `json:"kurlUrl"`
	UpgradeURL string `json:"upgradeUrl"`
	KurlRef    string `json:"kurlRef"`
}

func DequeueInstance(w http.ResponseWriter, r *http.Request) {
	testInstance, err := testinstance.GetNextEnqueued()
	if err != nil {
		if errors.Cause(err) != sql.ErrNoRows {
			w.WriteHeader(500)
			fmt.Printf("error dequeing instance: %s\n", err.Error())
			return
		}

		testInstance, err = testinstance.GetOldEnqueued()
		if err != nil {
			if errors.Cause(err) != sql.ErrNoRows {
				w.WriteHeader(500)
				fmt.Printf("error dequeing old instance: %s\n", err.Error())
				return
			}
			JSON(w, 200, []DequeueInstanceResponse{})
			return
		}
	}

	dequeueInstanceResponse := DequeueInstanceResponse{
		ID: testInstance.ID,

		OperatingSystemName:    testInstance.OSName,
		OperatingSystemVersion: testInstance.OSVersion,
		OperatingSystemImage:   testInstance.OSImage,
		OperatingSystemPreInit: testInstance.OSPreInit,

		KurlYAML:   testInstance.KurlYAML,
		KurlURL:    testInstance.KurlURL,
		UpgradeURL: testInstance.UpgradeURL,
		KurlRef:    testInstance.RefID,
	}

	JSON(w, 200, []DequeueInstanceResponse{
		dequeueInstanceResponse,
	})
}
