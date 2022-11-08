package k8sutil

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/client-go/kubernetes"
)

// DeploymentPods return a list of pods for provided deployment.
func DeploymentPods(ctx context.Context, cli kubernetes.Interface, ns, depname string) ([]corev1.Pod, error) {
	deploy, err := cli.AppsV1().Deployments(ns).Get(ctx, depname, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get deployment: %w", err)
	}

	pods, err := cli.CoreV1().Pods(ns).List(
		ctx, metav1.ListOptions{
			LabelSelector: labels.SelectorFromSet(deploy.Spec.Selector.MatchLabels).String(),
		},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to list pods for deploy: %w", err)
	}

	return pods.Items, nil
}
