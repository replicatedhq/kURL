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
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	restclient "k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	kubevirtv1 "kubevirt.io/client-go/api/v1"
	"kubevirt.io/client-go/kubecli"
)

var lastScheduledInstance = time.Now().Add(-time.Minute)

const Namespace = "default"

func MainRunLoop(runnerOptions types.RunnerOptions) error {
	fmt.Println("beginning main run loop")

	tempDir, err := ioutil.TempDir("", "")
	if err != nil {
		return errors.Wrap(err, "failed to create temp dir")
	}
	defer os.RemoveAll(tempDir)

	for {
		if err := CleanUpPVs(); err != nil {
			fmt.Println("PV clean up ERROR: ", err)
		}
		if err := CleanUpVMIs(); err != nil {
			fmt.Println("VMI clean up ERROR: ", err)
		}

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

				DockerEmail: os.Getenv("DOCKERHUB_EMAIL"),
				DockerUser:  os.Getenv("DOCKERHUB_USER"),
				DockerPass:  os.Getenv("DOCKERHUB_PASS"),
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
	clientset, err := GetClientset()
	if err != nil {
		return false, errors.Wrap(err, "failed to get clientset")
	}

	pods, err := clientset.CoreV1().Pods(Namespace).List(metav1.ListOptions{})
	if err != nil {
		return false, errors.Wrap(err, "failed to get pods in the default namespace")
	}

	// if there are pending pods, hold off until there are no longer pending pods
	for _, pod := range pods.Items {
		if pod.Status.Phase == v1.PodPending {
			return false, nil
		}
	}

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

func GetRestConfig() (*restclient.Config, error) {
	kubeconfig := filepath.Join(homeDir(), ".kube", "config")

	if os.Getenv("KUBECONFIG") != "" {
		kubeconfig = os.Getenv("KUBECONFIG")
	}

	// use the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return nil, errors.Wrap(err, "failed to build config")
	}
	return config, nil
}

func GetClientset() (kubernetes.Interface, error) {
	config, err := GetRestConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to get restconfig")
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create clientset")
	}

	return clientset, nil
}

func GetKubevirtClientset() (kubecli.KubevirtClient, error) {
	config, err := GetRestConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to get restconfig")
	}

	virtClient, err := kubecli.GetKubevirtClientFromRESTConfig(config)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create kubevirt clientset")
	}

	return virtClient, nil
}

func homeDir() string {
	if h := os.Getenv("HOME"); h != "" {
		return h
	}
	return os.Getenv("USERPROFILE") // windows
}

// CleanUpPVs cleans stale PV/PVC and localpath to reclaim space
func CleanUpPVs() error {
	clientset, err := GetClientset()
	if err != nil {
		return errors.Wrap(err, "failed to get clientset")
	}

	pvcs, err := clientset.CoreV1().PersistentVolumeClaims(Namespace).List(metav1.ListOptions{})

	// NOTE: OpenEbs webhook should be absent. For LocalPV volumes it has a bug preventing api calls, the webhook is only needed for cStor.
	for _, pvc := range pvcs.Items {
		// clean pvc older then 3 hours
		if time.Since(pvc.CreationTimestamp.Time).Hours() > 3 {
			pvc.ObjectMeta.SetFinalizers(nil)
			p, _ := clientset.CoreV1().PersistentVolumeClaims(Namespace).Update(&pvc)
			fmt.Printf("Removed finalizers on %s\n", p.Name)
			clientset.CoreV1().PersistentVolumeClaims(Namespace).Delete(pvc.Name, &metav1.DeleteOptions{})
			fmt.Printf("Deleted pvc %s\n", pvc.Name)
		}
	}

	pvs, err := clientset.CoreV1().PersistentVolumes().List(metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "failed to get pv list")
	}

	// finalizers might get pv in a stack state
	for _, pv := range pvs.Items {
		localPath := pv.Spec.Local.Path
		// deleting PVs older then 4 hours
		if time.Since(pv.CreationTimestamp.Time).Hours() > 4 && pv.ObjectMeta.DeletionTimestamp == nil {
			clientset.CoreV1().PersistentVolumes().Delete(pv.Name, &metav1.DeleteOptions{})
			fmt.Printf("Deleted pv %s\n", pv.Name)
			// Image file gets deleted and the space is reclamed on pv deletion
			// However local directory is left with tmpimage file, removing
			// 523M    /var/openebs/local/pvc-xxx
			err := os.RemoveAll(localPath)
			if err != nil {
				fmt.Printf("Failed to delete %s; ERROR: %s", localPath, err)
			}
		} else if pv.ObjectMeta.DeletionTimestamp != nil {
			// cleaning pv stack in Terminating state
			pv.ObjectMeta.SetFinalizers(nil)
			p, _ := clientset.CoreV1().PersistentVolumes().Update(&pv)
			fmt.Printf("Removed finalizers on %s, localPath: %s\n", p.Name, localPath)
		}
	}
	return nil
}

// CleanUpVMIs deletes "Succeeded" VMIs
func CleanUpVMIs() error {
	virtClient, err := GetKubevirtClientset()
	if err != nil {
		return errors.Wrap(err, "failed to get clientset")
	}

	vmiList, err := virtClient.VirtualMachineInstance(Namespace).List(&metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "failed to list vmis")
	}

	for _, vmi := range vmiList.Items {
		// cleanup succeeded VMIs
		// leaving them for a few hours for debug cases
		if vmi.Status.Phase == kubevirtv1.Succeeded && time.Since(vmi.CreationTimestamp.Time).Hours() > 3 {
			err := virtClient.VirtualMachineInstance(Namespace).Delete(vmi.Name, &metav1.DeleteOptions{})
			if err != nil {
				fmt.Printf("Failed to delete successful vmi %s: %v\n", vmi.Name, err)
			} else {
				fmt.Printf("Delete successful vmi %s\n", vmi.Name)
			}
		}

		// cleanup VMIs that have been running for more than two hours
		if vmi.Status.Phase == kubevirtv1.Running && time.Since(vmi.CreationTimestamp.Time).Minutes() > 120 {
			err := virtClient.VirtualMachineInstance(Namespace).Delete(vmi.Name, &metav1.DeleteOptions{})
			if err != nil {
				fmt.Printf("Failed to delete long-running vmi %s: %v\n", vmi.Name, err)
			} else {
				fmt.Printf("Delete long-running vmi %s\n", vmi.Name)
			}
		}
	}

	return nil
}
