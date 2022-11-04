package k8sutil

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// OwnedBy returns true if the provided object meta is among the provided list of owners.
func OwnedBy(ownedby []metav1.OwnerReference, ometa metav1.ObjectMeta) bool {
	for _, owner := range ownedby {
		if owner.UID != ometa.UID || owner.Name != ometa.Name {
			continue
		}
		return true
	}
	return false
}
