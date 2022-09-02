package cluster

import (
	"context"
	"fmt"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// NodeImages returns a map of node names to maps of images present on that node
func NodeImages(ctx context.Context, client kubernetes.Interface) (map[string]map[string]struct{}, error) {
	nodes, err := client.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("unable to list nodes: %w", err)
	}

	nodeImages := map[string]map[string]struct{}{}

	for _, node := range nodes.Items {
		thisNodeImages := map[string]struct{}{}
		for _, image := range node.Status.Images {
			for _, name := range image.Names {
				thisNodeImages[name] = struct{}{}
			}
		}
		nodeImages[node.Name] = thisNodeImages
	}

	return nodeImages, nil
}

// NodesMissingImages returns the list of nodes missing any one of the images in the provided list
func NodesMissingImages(ctx context.Context, client kubernetes.Interface, images []string) ([]string, error) {
	nodesImages, err := NodeImages(ctx, client)
	if err != nil {
		return nil, fmt.Errorf("unable to find what nodes have what images: %w", err)
	}

	missingNodes := map[string]struct{}{}
	for _, image := range images {
		for node, nodeImages := range nodesImages {
			_, foundImage := nodeImages[image]
			if !foundImage {
				missingNodes[node] = struct{}{}
			}
		}
	}

	missingNodesList := []string{}
	for missingNode := range missingNodes {
		missingNodesList = append(missingNodesList, missingNode)
	}

	return missingNodesList, nil
}
