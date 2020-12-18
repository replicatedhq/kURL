package handlers

import (
	"net/http"

	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type DequeueInstanceResponse struct {
	ID string `json:"id"`

	OperatingSystemName    string `json:"operatingSystemName"`
	OperatingSystemVersion string `json:"operatingSystemVersion"`
	OperatingSystemImage   string `json:"operatingSystemImage"`

	KurlYAML string `json:"kurlYaml"`
	KurlURL  string `json:"kurlUrl"`
	KurlRef  string `json:"kurlRef"`

	TimeoutAfter string `json:"timeoutAfter"`
}

func DequeueInstance(w http.ResponseWriter, r *http.Request) {
	testInstance, err := testinstance.GetNextEnqueued()
	if err != nil {
		testInstance, err = testinstance.GetOldEnqueued()
		if err != nil {
			JSON(w, 200, []DequeueInstanceResponse{})
			return
		}
	}

	dequeueInstanceResponse := DequeueInstanceResponse{
		ID: testInstance.ID,

		OperatingSystemName:    testInstance.OSName,
		OperatingSystemVersion: testInstance.OSVersion,
		OperatingSystemImage:   testInstance.OSImage,

		KurlYAML: testInstance.KurlYAML,
		KurlURL:  testInstance.KurlURL,
		KurlRef:  testInstance.RefID,

		TimeoutAfter: testInstance.TimeoutAfter,
	}

	JSON(w, 200, []DequeueInstanceResponse{
		dequeueInstanceResponse,
	})
}
