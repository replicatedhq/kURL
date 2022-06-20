package handlers

import (
	"database/sql"
	"fmt"
	"net/http"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance"
)

type DequeueInstanceResponse struct {
	ID                string `json:"id"`
	NumPrimaryNodes   int    `json:"numPrimaryNodes"`
	NumSecondaryNodes int    `json:"numSecondaryNodes"`
	Memory            string `json:"memory"`
	CPU               string `json:"cpu"`

	OperatingSystemName    string `json:"operatingSystemName"`
	OperatingSystemVersion string `json:"operatingSystemVersion"`
	OperatingSystemImage   string `json:"operatingSystemImage"`
	OperatingSystemPreInit string `json:"operatingSystemPreInit"`

	KurlYAML          string `json:"kurlYaml"`
	KurlURL           string `json:"kurlUrl"`
	KurlFlags         string `json:"kurlFlags"`
	UpgradeURL        string `json:"upgradeUrl"`
	SupportbundleYAML string `json:"supportbundleYaml"`
	PostInstallScript string `json:"postInstallScript"`
	PostUpgradeScript string `json:"postUpgradeScript"`
	KurlRef           string `json:"kurlRef"`
}

func DequeueInstance(w http.ResponseWriter, r *http.Request) {
	testInstance, err := testinstance.GetNextEnqueued()
	if err != nil {
		if errors.Cause(err) != sql.ErrNoRows {
			w.WriteHeader(500)
			fmt.Printf("error dequeing instance: %s\n", err.Error())
			return
		}
		JSON(w, 200, []DequeueInstanceResponse{})
		return
	}

	dequeueInstanceResponse := DequeueInstanceResponse{
		ID:                testInstance.ID,
		NumPrimaryNodes:   testInstance.NumPrimaryNodes,
		NumSecondaryNodes: testInstance.NumSecondaryNodes,
		Memory:            testInstance.Memory,
		CPU:               testInstance.CPU,

		OperatingSystemName:    testInstance.OSName,
		OperatingSystemVersion: testInstance.OSVersion,
		OperatingSystemImage:   testInstance.OSImage,
		OperatingSystemPreInit: testInstance.OSPreInit,

		KurlYAML:          testInstance.KurlYAML,
		KurlURL:           testInstance.KurlURL,
		KurlFlags:         testInstance.KurlFlags,
		UpgradeURL:        testInstance.UpgradeURL,
		SupportbundleYAML: testInstance.SupportbundleYAML,
		PostInstallScript: testInstance.PostInstallScript,
		PostUpgradeScript: testInstance.PostUpgradeScript,
		KurlRef:           testInstance.RefID,
	}

	JSON(w, 200, []DequeueInstanceResponse{
		dequeueInstanceResponse,
	})
}
