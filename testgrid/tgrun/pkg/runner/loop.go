package runner

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/pkg/errors"
	tghandlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/helpers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/types"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var lastScheduledInstance = time.Now().Add(-time.Minute)

const Namespace = "default"
const sleepTime = time.Second * 30

func MainRunLoop(runnerOptions types.RunnerOptions) error {
	fmt.Println("beginning main run loop")

	tempDir, err := ioutil.TempDir("", "")
	if err != nil {
		return errors.Wrap(err, "failed to create temp dir")
	}
	defer os.RemoveAll(tempDir)

	for {
		if err := CleanUpVMIs(); err != nil {
			fmt.Println("VMI clean up ERROR: ", err)
		}
		if err := CleanUpData(); err != nil {
			fmt.Println("PV clean up ERROR: ", err)
		}
		if err := ReportMetrics(runnerOptions); err != nil {
			fmt.Println("Metrics reporting ERROR: ", err)
		}

		canSchedule, err := canScheduleNewVM()
		if err != nil {
			return errors.Wrap(err, "failed to check if can schedule")
		}

		if !canSchedule {
			time.Sleep(sleepTime)
			continue
		}

		// hit the API and get the next
		resp, err := http.DefaultClient.Get(fmt.Sprintf("%s/v1/dequeue/instance", runnerOptions.APIEndpoint))
		if err != nil {
			fmt.Printf("Failed to get next run: %s\n", err)
			time.Sleep(sleepTime)
			continue
		}
		defer resp.Body.Close()
		body, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			return errors.Wrap(err, "failed to read body")
		}

		dequeueInstanceResponse := []tghandlers.DequeueInstanceResponse{}
		if err := json.Unmarshal(body, &dequeueInstanceResponse); err != nil {
			fmt.Printf("failed to unmarshal %q: %s\n", string(body), err.Error())
			time.Sleep(time.Minute * 5) // wait longer if there are errors with the API response
			continue
		}

		if len(dequeueInstanceResponse) == 0 {
			time.Sleep(sleepTime)
			continue
		}

		lastScheduledInstance = time.Now()

		uploadProxyURL, err := getUploadProxyURL()
		if err != nil {
			return errors.Wrap(err, "failed to get upload proxy url")
		}

		for _, dequeuedInstance := range dequeueInstanceResponse {
			singleTest := types.SingleRun{
				ID:                dequeuedInstance.ID,
				NumPrimaryNodes:   dequeuedInstance.NumPrimaryNodes,
				NumSecondaryNodes: dequeuedInstance.NumSecondaryNodes,
				Memory:            dequeuedInstance.Memory,
				CPU:               dequeuedInstance.CPU,

				OperatingSystemName:    dequeuedInstance.OperatingSystemName,
				OperatingSystemVersion: dequeuedInstance.OperatingSystemVersion,
				OperatingSystemImage:   dequeuedInstance.OperatingSystemImage,
				OperatingSystemPreInit: dequeuedInstance.OperatingSystemPreInit,

				PVCName: fmt.Sprintf("%s-disk", dequeuedInstance.ID),

				KurlYAML:          dequeuedInstance.KurlYAML,
				KurlURL:           dequeuedInstance.KurlURL,
				KurlFlags:         dequeuedInstance.KurlFlags,
				UpgradeURL:        dequeuedInstance.UpgradeURL,
				SupportbundleYAML: dequeuedInstance.SupportbundleYAML,
				PostInstallScript: dequeuedInstance.PostInstallScript,
				PostUpgradeScript: dequeuedInstance.PostUpgradeScript,
				KurlRef:           dequeuedInstance.KurlRef,

				TestGridAPIEndpoint: runnerOptions.APIEndpoint,
			}

			if err := Run(singleTest, uploadProxyURL, tempDir); err != nil {
				return errors.Wrap(err, "failed to run test")
			}
		}
	}
}

// canScheduleVM will return a boolean indicating if
// the current cluster can handle scheduling another
// test instance at this time
func canScheduleNewVM() (bool, error) {
	clientset, err := helpers.GetClientset()
	if err != nil {
		return false, errors.Wrap(err, "failed to get clientset")
	}

	pods, err := clientset.CoreV1().Pods(Namespace).List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		return false, errors.Wrap(err, "failed to get pods in the default namespace")
	}

	// if there are pending pods, hold off until there are no longer pending pods
	for _, pod := range pods.Items {
		if strings.HasPrefix(pod.Name, "virt-launcher-") && pod.Status.Phase == v1.PodPending {
			return false, nil
		}
	}

	return true, nil
}

func getUploadProxyURL() (string, error) {
	clientset, err := helpers.GetClientset()
	if err != nil {
		return "", errors.Wrap(err, "failed to get clientset")
	}

	svc, err := clientset.CoreV1().Services("cdi").Get(context.TODO(), "cdi-uploadproxy", metav1.GetOptions{})
	if err != nil {
		for i := 0; i < 5; i++ {
			time.Sleep(time.Minute)
			svc, err = clientset.CoreV1().Services("cdi").Get(context.TODO(), "cdi-uploadproxy", metav1.GetOptions{})
			if err == nil {
				break
			}
		}
		if err != nil {
			return "", errors.Wrap(err, "failed to get upload proxy service")
		}
	}

	return fmt.Sprintf("https://%s", svc.Spec.ClusterIP), nil
}
