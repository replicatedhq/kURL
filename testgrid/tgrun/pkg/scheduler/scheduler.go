package scheduler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"math/rand"
	"net/http"
	"os"
	"regexp"
	"time"

	"github.com/pkg/errors"
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	tghandlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/scheduler/types"
	"gopkg.in/yaml.v2"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var urlRegexp = regexp.MustCompile(`(https://[\w.]+)/([\w]+)`)

type kurlErrResp struct {
	Error struct {
		Message string `json:"message"`
	} `json:"error"`
}

func Run(schedulerOptions types.SchedulerOptions) error {
	rand.Seed(time.Now().UnixNano())

	plannedInstances := []tghandlers.PlannedInstance{}

	operatingSystems, err := getOses(schedulerOptions)
	if err != nil {
		return err
	}

	kurlPlans, err := getKurlPlans(schedulerOptions)
	if err != nil {
		return err
	}

	for _, instance := range kurlPlans {
		testSpec := instance.InstallerSpec
		// append sonobuoy for conformance testing
		if testSpec.Sonobuoy == nil || testSpec.Sonobuoy.Version == "" {
			testSpec.Sonobuoy = &kurlv1beta1.Sonobuoy{Version: "latest"}
		}

		// post it to the API to get a sha / id back
		installer := kurlv1beta1.Installer{
			TypeMeta: metav1.TypeMeta{
				APIVersion: "cluster.kurl.sh/v1beta1",
				Kind:       "Installer",
			},
			ObjectMeta: metav1.ObjectMeta{
				Name: "test",
			},
			Spec: testSpec,
		}

		installerYAML, err := json.Marshal(installer)
		if err != nil {
			return errors.Wrap(err, "failed to marshal json")
		}

		apiUrl := "https://kurl.sh/installer"
		if schedulerOptions.Staging {
			apiUrl = "https://staging.kurl.sh/installer"
		}

		req, err := http.NewRequest("POST", apiUrl, bytes.NewReader(installerYAML))
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

		var upgradeYAML, upgradeURL []byte
		if instance.UpgradeSpec != nil {
			installer.Spec = *instance.UpgradeSpec

			// append sonobuoy for conformance testing
			if installer.Spec.Sonobuoy == nil || installer.Spec.Sonobuoy.Version == "" {
				installer.Spec.Sonobuoy = &kurlv1beta1.Sonobuoy{Version: "latest"}
			}

			upgradeYAML, err = json.Marshal(installer)
			if err != nil {
				return errors.Wrap(err, "failed to marshal upgrade json")
			}

			req, err := http.NewRequest("POST", apiUrl, bytes.NewReader(upgradeYAML))
			if err != nil {
				return errors.Wrap(err, "failed to create request to submit installer upgrade spec")
			}
			req.Header.Set("Content-Type", "text/yaml")
			upgradeResp, err := http.DefaultClient.Do(req)
			if err != nil {
				return errors.Wrap(err, "failed to submit installer upgrade spec")
			}
			defer upgradeResp.Body.Close()

			upgradeURL, err = ioutil.ReadAll(upgradeResp.Body)
			if err != nil {
				return errors.Wrap(err, "failed to read upgrade response body")
			}

			if instance.Airgap || schedulerOptions.Airgap {
				upgradeURLString, err := getBundleFromURL(string(upgradeURL), schedulerOptions.KurlVersion)
				if err != nil {
					return errors.Wrapf(err, "generate airgap url from upgrade url %s", upgradeURL)
				}
				upgradeURL = []byte(upgradeURLString)
			} else {
				upgradeURLString, err := getInstallerURL(string(upgradeURL), schedulerOptions.KurlVersion)
				if err != nil {
					return errors.Wrapf(err, "generate versioned url from upgrade url %s", upgradeURL)
				}
				upgradeURL = []byte(upgradeURLString)
			}
		}

		var supportbundleYAML []byte
		if instance.SupportbundleSpec != nil {
			instance.SupportbundleSpec.APIVersion = "troubleshoot.sh/v1beta2"
			supportbundleYAML, err = json.Marshal(instance.SupportbundleSpec)
			if err != nil {
				return errors.Wrap(err, "failed to marshal support bundle json")
			}
		}

		// attempt to unmarshal installerURL as a kurl error message - if this works, it's not a URL
		var errMsg kurlErrResp
		err = json.Unmarshal(installerURL, &errMsg)
		if err == nil && errMsg.Error.Message != "" {
			return fmt.Errorf("error getting kurl spec url: %s", errMsg.Error.Message)
		}

		if instance.Airgap || schedulerOptions.Airgap {
			installerURLString, err := getBundleFromURL(string(installerURL), schedulerOptions.KurlVersion)
			if err != nil {
				return errors.Wrapf(err, "generate airgap url from installer url %s", installerURL)
			}
			installerURL = []byte(installerURLString)
		} else {
			installerURLString, err := getInstallerURL(string(installerURL), schedulerOptions.KurlVersion)
			if err != nil {
				return errors.Wrapf(err, "generate versioned url from installer url %s", installerURL)
			}
			installerURL = []byte(installerURLString)
		}

		for _, operatingSystem := range operatingSystems {
			testName := randSeq(16)

			isUnsupported := false
			if stringInSlice(operatingSystem.ID, instance.UnsupportedOSIDs) {
				isUnsupported = true
			}

			plannedInstance := tghandlers.PlannedInstance{
				ID: testName,

				KurlYAML: string(installerYAML),
				KurlURL:  string(installerURL),

				UpgradeYAML: string(upgradeYAML),
				UpgradeURL:  string(upgradeURL),

				SupportbundleYAML: string(supportbundleYAML),

				OperatingSystemName:    operatingSystem.Name,
				OperatingSystemVersion: operatingSystem.Version,
				OperatingSystemImage:   operatingSystem.VMImageURI,
				OperatingSystemPreInit: operatingSystem.PreInit,

				IsUnsupported: isUnsupported,
			}

			plannedInstances = append(plannedInstances, plannedInstance)
		}
	}

	if err := sendStartInstancesRequest(schedulerOptions, plannedInstances); err != nil {
		return errors.Wrap(err, "failed to report ref started")
	}

	fmt.Printf("Started tests on %d specs across %d images\n", len(kurlPlans), len(operatingSystems))

	return nil
}

func getKurlPlans(schedulerOptions types.SchedulerOptions) ([]types.Instance, error) {
	if schedulerOptions.Spec == "" {
		return nil, errors.New("spec required")
	}

	spec := schedulerOptions.Spec

	if _, err := os.Stat(spec); err == nil {
		b, err := ioutil.ReadFile(spec)
		if err != nil {
			return nil, err
		}
		spec = string(b)
	}

	var kurlPlans []types.Instance
	err := yaml.Unmarshal([]byte(spec), &kurlPlans)
	if err != nil {
		return nil, err
	}

	for idx := range kurlPlans {
		// ensure that installerSpec has a k8s and CRI version specified
		installerSpec := kurlPlans[idx].InstallerSpec
		isDistroDefined := (installerSpec.Kubernetes != nil && installerSpec.Kubernetes.Version != "") ||
			(installerSpec.RKE2 != nil && installerSpec.RKE2.Version != "") ||
			(installerSpec.K3S != nil && installerSpec.K3S.Version != "")
		if !isDistroDefined {
			installerSpec.Kubernetes = &kurlv1beta1.Kubernetes{Version: "latest"}
		}

		isDistroRancher := (installerSpec.RKE2 != nil && installerSpec.RKE2.Version != "") ||
			(installerSpec.K3S != nil && installerSpec.K3S.Version != "")
		if !isDistroRancher &&
			(installerSpec.Docker == nil || installerSpec.Docker.Version == "") &&
			(installerSpec.Containerd == nil || installerSpec.Containerd.Version == "") {
			installerSpec.Docker = &kurlv1beta1.Docker{Version: "latest"}
		}
	}

	return kurlPlans, nil
}

func getOses(schedulerOptions types.SchedulerOptions) ([]types.OperatingSystemImage, error) {
	if schedulerOptions.OSSpec == "" {
		return nil, errors.New("os spec required")
	}

	var oses []types.OperatingSystemImage

	spec := schedulerOptions.OSSpec

	if _, err := os.Stat(spec); err == nil {
		b, err := ioutil.ReadFile(spec)
		if err != nil {
			return nil, err
		}
		spec = string(b)
	}

	err := yaml.Unmarshal([]byte(spec), &oses)
	if err != nil {
		return nil, err
	}

	return oses, nil
}

func sendStartInstancesRequest(schedulerOptions types.SchedulerOptions, plannedInstances []tghandlers.PlannedInstance) error {
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
	req.SetBasicAuth("token", schedulerOptions.APIToken)
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

func stringInSlice(s string, slice []string) bool {
	for _, v := range slice {
		if s == v {
			return true
		}
	}
	return false
}

func getInstallerURL(url, kurlVersion string) (string, error) {
	matches := urlRegexp.FindStringSubmatch(url)

	if len(matches) != 3 {
		return "", fmt.Errorf("unable to parse url %q", url)
	}

	if kurlVersion == "" {
		return url, nil
	}

	return fmt.Sprintf("%s/version/%s/%s", matches[1], kurlVersion, matches[2]), nil
}

func getBundleFromURL(url, kurlVersion string) (string, error) {
	matches := urlRegexp.FindStringSubmatch(url)

	if len(matches) != 3 {
		return "", fmt.Errorf("unable to parse url %q", url)
	}

	if kurlVersion == "" {
		return fmt.Sprintf("%s/bundle/%s.tar.gz", matches[1], matches[2]), nil
	}

	return fmt.Sprintf("%s/bundle/version/%s/%s.tar.gz", matches[1], kurlVersion, matches[2]), nil
}
