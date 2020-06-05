package runner

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/pkg/errors"
	tghandlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/types"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

var lastScheduledInstance = time.Now().Add(-time.Minute)

func MainRunLoop(runnerOptions types.RunnerOptions) error {
	fmt.Println("beginning main run loop")

	for {
		canSchedule, err := canScheduleNewVM()
		if err != nil {
			return errors.Wrap(err, "failed to check if can schedule")
		}

		if !canSchedule {
			time.Sleep(time.Second * 15)
			continue
		}

		// hit the API and get the next
		resp, err := http.DefaultClient.Get(fmt.Sprintf("%s/v1/dequeue/instance", runnerOptions.APIEndpoint))
		if err != nil {
			return errors.Wrap(err, "failed to get next run")
		}
		defer resp.Body.Close()
		body, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			return errors.Wrap(err, "failed to read body")
		}

		dequeueInstanceResponse := []tghandlers.DequeueInstanceResponse{}
		if err := json.Unmarshal(body, &dequeueInstanceResponse); err != nil {
			return errors.Wrapf(err, "failed to unmarshal: %s", body)
		}

		if len(dequeueInstanceResponse) == 0 {
			time.Sleep(time.Second * 15)
			continue
		}

		lastScheduledInstance = time.Now()

		uploadProxyURL, err := getUploadProxyURL()
		if err != nil {
			return errors.Wrap(err, "failed to get upload proxy url")
		}

		for _, dequeuedInstance := range dequeueInstanceResponse {
			singleTest := types.SingleRun{
				ID: dequeuedInstance.ID,

				OperatingSystemName:    dequeuedInstance.OperatingSystemName,
				OperatingSystemVersion: dequeuedInstance.OperatingSystemVersion,
				OperatingSystemImage:   dequeuedInstance.OperatingSystemImage,

				PVCName: fmt.Sprintf("%s-disk", dequeuedInstance.ID),

				KurlYAML: dequeuedInstance.KurlYAML,
				KurlURL:  dequeuedInstance.KurlURL,
				KurlRef:  dequeuedInstance.KurlRef,

				TestGridAPIEndpoint: runnerOptions.APIEndpoint,
			}

			if err := Run(singleTest, uploadProxyURL); err != nil {
				return errors.Wrap(err, "failed to run test")
			}
		}
	}
}

// canScheduleVM will return a boolean indicating if
// the current cluster can handle scheduling another
// test instance at this time
func canScheduleNewVM() (bool, error) {
	if lastScheduledInstance.Add(time.Minute).After(time.Now()) {
		return false, nil
	}

	// TODO check load and resource availability

	return true, nil
}

func getUploadProxyURL() (string, error) {
	clientset, err := GetClientset()
	if err != nil {
		return "", errors.Wrap(err, "failed to get clientset")
	}

	svc, err := clientset.CoreV1().Services("cdi").Get("cdi-uploadproxy", metav1.GetOptions{})
	if err != nil {
		return "", errors.Wrap(err, "failed to get upload proxy service")
	}

	return fmt.Sprintf("https://%s", svc.Spec.ClusterIP), nil
}

func GetClientset() (*kubernetes.Clientset, error) {
	kubeconfig := filepath.Join(homeDir(), ".kube", "config")

	if os.Getenv("KUBECONFIG") != "" {
		kubeconfig = os.Getenv("KUBECONFIG")
	}

	// use the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return nil, errors.Wrap(err, "failed to build config")
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create clientset")
	}

	return clientset, nil
}

func homeDir() string {
	if h := os.Getenv("HOME"); h != "" {
		return h
	}
	return os.Getenv("USERPROFILE") // windows
}
