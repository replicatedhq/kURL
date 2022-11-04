package k8sutil

import (
	"context"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// DeploymentPods return a list of pods for provided deployment.
func DeploymentPods(ctx context.Context, cli kubernetes.Interface, ns, depname string) ([]corev1.Pod, error) {
	deploy, err := cli.AppsV1().Deployments(ns).Get(ctx, depname, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("unable to get deployment: %w", err)
	}

	rss, err := cli.AppsV1().ReplicaSets(ns).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("unable to get replicaset: %w", err)
	}

	var chrs *appsv1.ReplicaSet
	for _, rs := range rss.Items {
		if !OwnedBy(rs.OwnerReferences, deploy.ObjectMeta) {
			continue
		}
		chrs = &rs
		break
	}
	if chrs == nil {
		return nil, fmt.Errorf("unable to find replicaset for deploy: %s/%s", ns, depname)
	}

	pods, err := cli.CoreV1().Pods(ns).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("unable to get pods: %w", err)
	}

	result := []corev1.Pod{}
	for _, pod := range pods.Items {
		if !OwnedBy(pod.OwnerReferences, chrs.ObjectMeta) {
			continue
		}
		result = append(result, pod)
	}
	return result, nil
}
