package runner

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/pkg/errors"
	handlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	kubevirtv1 "kubevirt.io/api/core/v1"
	"kubevirt.io/client-go/kubecli"
)

const CleanUpVMIsDurationMinutes = float64(90)

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

	runningVMIs := map[string][]string{}

	for _, vmi := range vmiList.Items {
		// fail VMIs that have been running for more than 1.5 hours
		// the in-script timeout for install is 30m, upgrade is 45m
		if vmi.Status.Phase == kubevirtv1.Running && time.Since(vmi.CreationTimestamp.Time).Minutes() > CleanUpVMIsDurationMinutes {
			if apiEndpoint := vmi.Annotations["testgrid.kurl.sh/apiendpoint"]; apiEndpoint != "" {
				url := fmt.Sprintf("%s/v1/instance/%s/finish", apiEndpoint, vmi.Name)
				data := `{"success": false, "failureReason": "timeout"}`
				resp, err := http.Post(url, "application/json", strings.NewReader(data))
				if err != nil {
					log.Printf("Failed to post timeout failure to testgrid api for vmi %s: %v", vmi.Name, err)
				} else {
					resp.Body.Close()
				}
			}
		}

		// cleanup VMIs that have been around for more than 1.5 hours
		if time.Since(vmi.CreationTimestamp.Time).Minutes() > CleanUpVMIsDurationMinutes {
			err := virtClient.VirtualMachineInstance(Namespace).Delete(vmi.Name, &metav1.DeleteOptions{})
			if err != nil {
				log.Printf("Failed to delete vmi %s: %v", vmi.Name, err)
			} else {
				log.Printf("Delete vmi %s", vmi.Name)
			}
		} else if vmi.Status.Phase == kubevirtv1.Running {
			if apiEndpoint := vmi.Annotations["testgrid.kurl.sh/apiendpoint"]; apiEndpoint != "" {
				runningVMIs[apiEndpoint] = append(runningVMIs[apiEndpoint], vmi.Name)
			}
		}
	}

	for apiEndpoint, vmis := range runningVMIs {
		err := cleanupFinishedInstances(virtClient, apiEndpoint, vmis)
		if err != nil {
			log.Printf("Failed to cleanup finished instances for api endpoint %s: %v", apiEndpoint, err)
		}
	}

	return nil
}

// cleanupFinishedInstances will compare VMI IDs to a list of finished instances returned from the
// API and delete ones that have finished. This is meant as an optimization as the VM takes time to
// spin down on server shutdown.
func cleanupFinishedInstances(virtClient kubecli.KubevirtClient, apiEndpoint string, vmis []string) error {
	url := fmt.Sprintf("%s/v1/instances/finished?duration=%s", apiEndpoint, (time.Duration(CleanUpVMIsDurationMinutes) * time.Minute))
	resp, err := http.Get(url)
	if err != nil {
		return errors.Wrap(err, "get finished instances")
	}
	defer resp.Body.Close()

	dec := json.NewDecoder(resp.Body)
	response := handlers.ListFinishedInstancesResponse{}
	if err := dec.Decode(&response); err != nil {
		return errors.Wrap(err, "decode list finished instances response")
	}

	for _, instance := range response.Instances {
		for _, vmiName := range vmis {
			parts := strings.SplitN(vmiName, "-", 2)
			if instance.ID == parts[0] {
				err := virtClient.VirtualMachineInstance(Namespace).Delete(vmiName, &metav1.DeleteOptions{})
				if err != nil {
					log.Printf("Failed to delete vmi %s: %v", vmiName, err)
				} else {
					log.Printf("Delete vmi %s", vmiName)
				}
			}
		}
	}

	return nil
}

// CleanUpData cleans stale PV/PVC/Secrets and localpath to reclaim space
func CleanUpData() error {
	clientset, err := GetClientset()
	if err != nil {
		return errors.Wrap(err, "failed to get clientset")
	}

	if err := cleanupPVCs(clientset); err != nil {
		return err
	}
	if err := cleanupPVs(clientset); err != nil {
		return err
	}
	if err := cleanupSecrets(clientset); err != nil {
		return err
	}
	return nil
}

func cleanupPVCs(clientset *kubernetes.Clientset) error {
	pvcs, err := clientset.CoreV1().PersistentVolumeClaims(Namespace).List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "failed to get pvc list")
	}

	// NOTE: OpenEbs webhook should be absent. For LocalPV volumes it has a bug preventing api calls, the webhook is only needed for cStor.
	for _, pvc := range pvcs.Items {
		// clean pvc older then 3 hours
		if time.Since(pvc.CreationTimestamp.Time).Hours() > 3 {
			pvc.ObjectMeta.SetFinalizers(nil)
			p, err := clientset.CoreV1().PersistentVolumeClaims(Namespace).Update(context.TODO(), &pvc, metav1.UpdateOptions{})
			if err != nil {
				log.Printf("Failed removing finalizers for pvc %s; EROOR: %s", p.Name, err)
			} else {
				log.Printf("Removed finalizers on %s", p.Name)
			}

			err = clientset.CoreV1().PersistentVolumeClaims(Namespace).Delete(context.TODO(), pvc.Name, metav1.DeleteOptions{})
			if err != nil {
				log.Printf("Failed deleting pvc %s; EROOR: %s", pvc.Name, err)
			} else {
				log.Printf("Deleted pvc %s", pvc.Name)
			}
		}
	}
	return nil
}

func cleanupPVs(clientset *kubernetes.Clientset) error {
	pvs, err := clientset.CoreV1().PersistentVolumes().List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "failed to get pv list")
	}

	// finalizers might get pv in a stack state
	for _, pv := range pvs.Items {
		localPath := pv.Spec.Local.Path
		// deleting PVs older then 4 hours
		if time.Since(pv.CreationTimestamp.Time).Hours() > 4 && pv.ObjectMeta.DeletionTimestamp == nil {
			clientset.CoreV1().PersistentVolumes().Delete(context.TODO(), pv.Name, metav1.DeleteOptions{})
			log.Printf("Deleted pv %s", pv.Name)
			// Image file gets deleted and the space is reclamed on pv deletion
			// However local directory is left with tmpimage file, removing
			// 523M    /var/openebs/local/pvc-xxx
			err := os.RemoveAll(localPath)
			if err != nil {
				log.Printf("Failed to delete %s; ERROR: %s", localPath, err)
			}
		} else if pv.ObjectMeta.DeletionTimestamp != nil {
			// cleaning pv stack in Terminating state
			pv.ObjectMeta.SetFinalizers(nil)
			p, err := clientset.CoreV1().PersistentVolumes().Update(context.TODO(), &pv, metav1.UpdateOptions{})
			if err != nil {
				log.Printf("Failed removing finalizers for pv %s; EROOR: %s", p.Name, err)
			} else {
				log.Printf("Removed finalizers on %s, localPath: %s", p.Name, localPath)
			}
		}
	}
	return nil
}

// CleanUpSecrets removes stale cloud-init configurations stored in secrets and prevents errors on interupted runs
func cleanupSecrets(clientset *kubernetes.Clientset) error {
	secrets, err := clientset.CoreV1().Secrets(Namespace).List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "failed to get secrets list")
	}

	for _, sec := range secrets.Items {
		// Delete stale secrets older then 5 hours
		if len(sec.Name) > 6 && sec.Name[:5] == "cloud" && time.Since(sec.CreationTimestamp.Time).Hours() > 5 {
			clientset.CoreV1().Secrets(Namespace).Delete(context.TODO(), sec.Name, metav1.DeleteOptions{})
			log.Printf("Deleted stale secret %s", sec.Name)
		}
	}
	return nil
}
