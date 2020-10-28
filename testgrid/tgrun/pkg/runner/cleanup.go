package runner

import (
	"fmt"
	"os"
	"time"

	"github.com/pkg/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	kubevirtv1 "kubevirt.io/client-go/api/v1"
)

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
	pvcs, err := clientset.CoreV1().PersistentVolumeClaims(Namespace).List(metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "failed to get pvc list")
	}

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
	return nil
}

func cleanupPVs(clientset *kubernetes.Clientset) error {
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

// CleanUpSecrets removes stale cloud-init configurations stored in secrets and prevents errors on interupted runs
func cleanupSecrets(clientset *kubernetes.Clientset) error {
	secrets, err := clientset.CoreV1().Secrets(Namespace).List(metav1.ListOptions{})
	if err != nil {
		return errors.Wrap(err, "failed to get secrets list")
	}

	for _, sec := range secrets.Items {
		// Delete stale secrets older then 5 hours
		if len(sec.Name) > 6 && sec.Name[:5] == "cloud" && time.Since(sec.CreationTimestamp.Time).Hours() > 5 {
			clientset.CoreV1().Secrets(Namespace).Delete(sec.Name, &metav1.DeleteOptions{})
			fmt.Printf("Deleted stale secret %s\n", sec.Name)
		}
	}
	return nil
}
