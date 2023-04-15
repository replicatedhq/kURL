package k8sutil

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// WaitForDaemonsetRollout waits for a daemonset to rollout.
func WaitForDaemonsetRollout(ctx context.Context, cli kubernetes.Interface, ds *appsv1.DaemonSet, timeout time.Duration) error {
	nodes, err := cli.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return fmt.Errorf("failed to list nodes: %w", err)
	}
	var endAt = time.Now().Add(timeout)
	healthyCount, desiredCount := 0, 10
	for {
		gotDS, err := cli.AppsV1().DaemonSets(ds.Namespace).Get(ctx, ds.Name, metav1.GetOptions{})
		if err != nil {
			return fmt.Errorf("failed getting daemonset: %w", err)
		}
		if gotDS.Status.NumberReady == int32(len(nodes.Items)) {
			if healthyCount++; healthyCount == desiredCount {
				return nil
			}
		}
		if time.Sleep(time.Second); time.Now().After(endAt) {
			return fmt.Errorf("timeout waiting for daemonset to rollout")
		}
	}
}
