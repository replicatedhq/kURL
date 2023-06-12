package k8sutil

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

func TolerationsForAllNodes(ctx context.Context, cli kubernetes.Interface) ([]corev1.Toleration, error) {
	nodes, err := cli.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to list nodes: %w", err)
	}
	seen := map[corev1.Toleration]bool{}
	var tolerations []corev1.Toleration
	for _, node := range nodes.Items {
		forNode := TolerationsForNode(node)
		for _, t := range forNode {
			if _, ok := seen[t]; ok {
				continue
			}
			seen[t] = true
			tolerations = append(tolerations, t)
		}
	}
	return tolerations, nil
}

// TolerationsForNode returns a list of tolerations that matches the provided node.
func TolerationsForNode(node corev1.Node) []corev1.Toleration {
	tolerations := []corev1.Toleration{}
	for _, taint := range node.Spec.Taints {
		toleration := corev1.Toleration{
			Key:      taint.Key,
			Operator: corev1.TolerationOpExists,
			Effect:   taint.Effect,
		}
		tolerations = append(tolerations, toleration)
	}
	return tolerations
}

// NodeInternalIP returns the node internal ip address for the provided node.
func NodeInternalIP(node corev1.Node) (string, error) {
	for _, ip := range node.Status.Addresses {
		if ip.Type != corev1.NodeInternalIP {
			continue
		}
		return ip.Address, nil
	}
	return "", fmt.Errorf("failed to determine ip address for node %s", node.Name)
}

// NodeInternalIPByNodeName returns the node internal ip address for the provided node name.
func NodeInternalIPByNodeName(nodes []corev1.Node, nodeName string) (string, error) {
	for _, node := range nodes {
		if node.Name != nodeName {
			continue
		}
		return NodeInternalIP(node)
	}
	return "", fmt.Errorf("failed to find node %s", nodeName)
}
