package k8sutil

import (
	"context"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// WaitForDeploymentReady polls every 5 seconds until either the provided deployment is ready or
// the context is closed.
func WaitForDeploymentReady(ctx context.Context, clientset kubernetes.Interface, namespace, name string) error {
	for {
		if err := ctx.Err(); err != nil {
			return err
		}

		dep, err := clientset.AppsV1().Deployments(namespace).Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			return err
		}
		if IsDeploymentReady(*dep) {
			return nil
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(5 * time.Second):
			// continue
		}
	}
}

// IsDeploymentReady returns true if the provided deployment is ready.
func IsDeploymentReady(dep appsv1.Deployment) bool {
	return dep.Status.Replicas == dep.Status.UpdatedReplicas &&
		dep.Status.Replicas == dep.Status.AvailableReplicas &&
		dep.Status.Replicas == dep.Status.ReadyReplicas
}
