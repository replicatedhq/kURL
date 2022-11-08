package clusterspace

import (
	"context"
	"fmt"
	"log"

	"github.com/replicatedhq/kurl/pkg/k8sutil"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

// K8SUtils provides tooling for common operations used by multiple storage free checkers.
type K8SUtils struct {
	log *log.Logger
	cli kubernetes.Interface
	cfg *rest.Config
}

// PVSReservationPerNode return the sum of space of all pvs being served per node. this function
// also returns sum of space in pvs that exist bur are not in attached to any pod.
func (k *K8SUtils) PVSReservationPerNode(ctx context.Context, scname string) (map[string]int64, int64, error) {
	pvs, err := k8sutil.PVSByStorageClass(ctx, k.cli, scname)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to get pvs: %w", err)
	}

	pvcs, err := k8sutil.PVCSForPVs(ctx, k.cli, pvs)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to get pvcs for pvs: %w", err)
	}

	var detached int64
	var attached = map[string]int64{}
	for pvidx, pvc := range pvcs {
		pv, ok := pvs[pvidx]
		if !ok {
			pvcidx := fmt.Sprintf("%s/%s", pvc.Namespace, pvc.Name)
			return nil, 0, fmt.Errorf("pv %s for pvc %s not found", pvidx, pvcidx)
		}

		pods, err := k.cli.CoreV1().Pods(pvc.Namespace).List(ctx, metav1.ListOptions{})
		if err != nil {
			return nil, 0, fmt.Errorf("failed to list pods in namespace %s: %w", pvc.Namespace, err)
		}

		var inuse bool
		for _, pod := range pods.Items {
			if !k8sutil.PodUsesPVC(pod, pvc) {
				continue
			}

			bytes, dec := pv.Spec.Capacity.Storage().AsInt64()
			if !dec {
				return nil, 0, fmt.Errorf("failed to parse pv %s storage size: %w", pvidx, err)
			}
			inuse = true
			attached[pod.Spec.NodeName] += bytes
			break
		}

		if inuse {
			continue
		}

		bytes, dec := pv.Spec.Capacity.Storage().AsInt64()
		if !dec {
			return nil, 0, fmt.Errorf("failed to parse pv %s storage size: %w", pvidx, err)
		}
		detached += bytes
	}

	return attached, detached, nil
}

// NewK8sUtils returns a new auxiliar entity for kubernetes related operatios.
func NewK8sUtils(log *log.Logger, cli kubernetes.Interface, cfg *rest.Config) *K8SUtils {
	return &K8SUtils{log: log, cli: cli, cfg: cfg}
}
