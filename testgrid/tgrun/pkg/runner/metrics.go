package runner

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	"github.com/pkg/errors"
	tghandlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/types"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	kubevirtv1 "kubevirt.io/api/core/v1"
)

func ReportMetrics(runnerOptions types.RunnerOptions) error {
	runningVMIs, err := countRunningVMIs()
	if err != nil {
		return errors.Wrap(err, "failed to count running vmis")
	}

	freeCPU, freeRAM, err := getFreeResources()
	if err != nil {
		return errors.Wrap(err, "failed to get free resources")
	}

	hostName, err := os.Hostname()
	if err != nil {
		return errors.Wrap(err, "failed to get hostname")
	}

	runnerStatusRequest := tghandlers.RunnerStatusRequest{
		FreeCPU:      freeCPU,
		FreeRAM:      freeRAM,
		RunningTests: float64(runningVMIs),
		Hostname:     hostName,
	}
	b, err := json.Marshal(runnerStatusRequest)
	if err != nil {
		return errors.Wrap(err, "failed to marshal metrics")
	}

	_, err = http.NewRequest("POST", fmt.Sprintf("%s/v1/runner/status", runnerOptions.APIEndpoint), bytes.NewReader(b))
	if err != nil {
		return errors.Wrap(err, "failed to send metrics")
	}

	return nil
}

// countRunningVMIs gets a count of the number of running VMIs
func countRunningVMIs() (int, error) {
	virtClient, err := GetKubevirtClientset()
	if err != nil {
		return 0, errors.Wrap(err, "failed to get clientset")
	}

	vmiList, err := virtClient.VirtualMachineInstance(Namespace).List(&metav1.ListOptions{})
	if err != nil {
		return 0, errors.Wrap(err, "failed to list vmis")
	}

	runningVMIs := 0
	for _, vmi := range vmiList.Items {
		if vmi.Status.Phase == kubevirtv1.Running {
			runningVMIs += 1
		}
	}

	return runningVMIs, nil
}

func getFreeResources() (float64, float64, error) {
	clientset, err := GetClientset()
	if err != nil {
		return 0, 0, errors.Wrap(err, "failed to get clientset")
	}

	nodes, err := clientset.CoreV1().Nodes().List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		return 0, 0, errors.Wrap(err, "failed to get nodes")
	}

	freeCPU := float64(0)
	freeRAM := float64(0)

	for _, node := range nodes.Items {
		freeCPU += node.Status.Allocatable.Cpu().AsApproximateFloat64()
		freeRAM += node.Status.Allocatable.Memory().AsApproximateFloat64()
	}
	return freeCPU, freeRAM, nil
}
