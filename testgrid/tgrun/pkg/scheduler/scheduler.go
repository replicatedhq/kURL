package scheduler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"math/rand"
	"net/http"
	"time"

	"github.com/pkg/errors"
	tghandlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/instances"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// hack
var previouslyGeneratedNames = []string{}

type kurlErrResp struct {
	Error struct {
		Message string `json:"message"`
	} `json:"error"`
}

func Run(schedulerOptions types.SchedulerOptions) error {
	rand.Seed(time.Now().UnixNano())

	plannedInstances := []tghandlers.PlannedInstance{}

	for _, testSpec := range instances.Instances {
		// post it to the API to get a sha / id back
		installer := types.Installer{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "cluster.kurl.sh/v1beta1",
				Kind:       "Installer",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "test",
			},
			Spec: testSpec,
		}

		b, err := json.Marshal(installer)
		if err != nil {
			return errors.Wrap(err, "failed to marshal json")
		}

		apiUrl := "https://kurl.sh/installer"
		if testSpec.IsStaging {
			apiUrl = "https://staging.kurl.sh/installer"
		}

		req, err := http.NewRequest("POST", apiUrl, bytes.NewReader(b))
		if err != nil {
			return errors.Wrap(err, "failed to create request to submit installer spec")
		}
		req.Header.Set("Content-Type", "text/yaml")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return errors.Wrap(err, "failed to submit installer spec")
		}
		defer resp.Body.Close()

		installerURL, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			return errors.Wrap(err, "failed to read response body")
		}

		// attempt to unmarshal installerURL as a kurl error message - if this works, it's not a URL
		var errMsg kurlErrResp
		err = json.Unmarshal(installerURL, &errMsg)
		if err == nil && errMsg.Error.Message != "" {
			return fmt.Errorf("error getting kurl spec url: %s", errMsg.Error.Message)
		}

		for _, operatingSystem := range operatingSystems {
			testName := randSeq(6)

			plannedInstance := tghandlers.PlannedInstance{
				ID: testName,

				KurlYAML: string(b),
				KurlURL:  string(installerURL),

				OperatingSystemName:    operatingSystem.Name,
				OperatingSystemVersion: operatingSystem.Version,
				OperatingSystemImage:   operatingSystem.VMImageURI,
			}

			plannedInstances = append(plannedInstances, plannedInstance)
		}
	}

	if err := reportStarted(schedulerOptions, plannedInstances); err != nil {
		return errors.Wrap(err, "failed to report ref started")
	}

	fmt.Printf("Started tests on %d specs across %d images\n", len(instances.Instances), len(operatingSystems))

	return nil
}

func reportStarted(schedulerOptions types.SchedulerOptions, plannedInstances []tghandlers.PlannedInstance) error {
	startRefRequest := tghandlers.StartRefRequest{
		Overwrite: schedulerOptions.OverwriteRef,
		Instances: plannedInstances,
	}

	b, err := json.Marshal(startRefRequest)
	if err != nil {
		return errors.Wrap(err, "failed to marshal request")
	}

	req, err := http.NewRequest("POST", fmt.Sprintf("%s/v1/ref/%s/start", schedulerOptions.APIEndpoint, schedulerOptions.Ref), bytes.NewReader(b))
	if err != nil {
		return errors.Wrap(err, "failed to create request to start run")
	}
	req.Header.Set("Content-Type", "application/json")
	req.ContentLength = int64(len(b))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return errors.Wrap(err, "failed to execute request to start run")
	}

	if resp.StatusCode == 419 {
		return errors.New("ref already exists")
	}

	if resp.StatusCode != 200 {
		return fmt.Errorf("got unexpected error code starting run: %d", resp.StatusCode)
	}

	return nil
}

var letters = []rune("abcdefghijklmnopqrstuvwxyz")

func randSeq(n int) string {
	b := make([]rune, n)
	for i := range b {
		b[i] = letters[rand.Intn(len(letters))]
	}
	return string(b)
}
