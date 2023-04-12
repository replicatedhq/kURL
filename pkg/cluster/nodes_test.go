package cluster

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"testing"

	"github.com/replicatedhq/kurl/pkg/rook/testfiles"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/fake"
)

// test function only, contains panics
func runtimeFromNodesJSON(nodeListJSON []byte) []runtime.Object {
	podList := corev1.NodeList{}
	err := json.Unmarshal(nodeListJSON, &podList)
	if err != nil {
		panic(err) // this is only called for unit tests, not at runtime
	}

	runtimeObjects := []runtime.Object{}
	for idx := range podList.Items {
		runtimeObjects = append(runtimeObjects, &podList.Items[idx])
	}
	return runtimeObjects
}

func TestNodesMissingImages(t *testing.T) {
	tests := []struct {
		name           string
		resources      []runtime.Object
		images         []string
		nodeImagesOpts NodeImagesJobOptions
		wantNodes      []string
	}{
		{
			name:      "an image that does not exist should return the node",
			resources: runtimeFromNodesJSON(testfiles.UpgradedNodeLess50Images),
			images:    []string{"doesnotexist"},
			wantNodes: []string{"laverya-rook-kubernetes-upgrade"},
		},
		{
			name:      "an image that does exist should not return the node",
			resources: runtimeFromNodesJSON(testfiles.UpgradedNodeLess50Images),
			images:    []string{"registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.5.0"},
			wantNodes: []string{},
		},
		{
			name:      "an image that does exist and one that does should return the node",
			resources: runtimeFromNodesJSON(testfiles.UpgradedNodeLess50Images),
			images:    []string{"registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.5.0", "doesnotexist"},
			wantNodes: []string{"laverya-rook-kubernetes-upgrade"},
		},
		{
			name:      "an image that is not in canonical format should not return the node",
			resources: runtimeFromNodesJSON(testfiles.UpgradedNodeLess50Images),
			images:    []string{"rook/ceph:v1.5.12"},
			wantNodes: []string{},
		},

		{
			name:      "an image that does not exist on the Node resource but does from the job response should not return the node",
			resources: runtimeFromNodesJSON(testfiles.UpgradedNode),
			images:    []string{"docker.io/library/doesnotexist:latest"},
			nodeImagesOpts: NodeImagesJobOptions{
				nodeImagesJobRunner: func(ctx context.Context, i kubernetes.Interface, l *log.Logger, n corev1.Node, nijo NodeImagesJobOptions) ([]corev1.ContainerImage, error) {
					return []corev1.ContainerImage{
						{
							Names: []string{"doesnotexist"},
						},
					}, nil
				},
			},
			wantNodes: []string{},
		},
		{
			name:      "an image that exists on the Node resource but does not from the job response should return the node",
			resources: runtimeFromNodesJSON(testfiles.UpgradedNode),
			images:    []string{"registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.5.0"},
			nodeImagesOpts: NodeImagesJobOptions{
				nodeImagesJobRunner: func(ctx context.Context, i kubernetes.Interface, l *log.Logger, n corev1.Node, nijo NodeImagesJobOptions) ([]corev1.ContainerImage, error) {
					return []corev1.ContainerImage{
						{
							Names: []string{"doesnotexist"},
						},
					}, nil
				},
			},
			wantNodes: []string{"laverya-rook-kubernetes-upgrade"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)
			clientset := fake.NewSimpleClientset(tt.resources...)
			logger := log.New(io.Discard, "", 0)

			gotNodes, err := NodesMissingImages(context.Background(), clientset, logger, tt.images, tt.nodeImagesOpts)
			req.NoError(err)
			req.ElementsMatch(tt.wantNodes, gotNodes)
		})
	}
}

func TestNodeListMissingImages(t *testing.T) {
	tests := []struct {
		name           string
		resources      []runtime.Object
		node           string
		images         []string
		nodeImagesOpts NodeImagesJobOptions
		wantImages     []string
		wantErr        bool
	}{
		{
			name:       "an image that does not exist should return",
			resources:  runtimeFromNodesJSON(testfiles.UpgradedNodeLess50Images),
			node:       "laverya-rook-kubernetes-upgrade",
			images:     []string{"doesnotexist", "k8s.gcr.io/kube-scheduler:v1.20.15", "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.5.0", "doesnotexist2"},
			wantImages: []string{"doesnotexist", "doesnotexist2"},
		},
		{
			name:       "no missing images should return empty",
			resources:  runtimeFromNodesJSON(testfiles.UpgradedNodeLess50Images),
			node:       "laverya-rook-kubernetes-upgrade",
			images:     []string{"k8s.gcr.io/kube-scheduler:v1.20.15", "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.5.0"},
			wantImages: []string{},
		},
		{
			name:       "only missing images should return",
			resources:  runtimeFromNodesJSON(testfiles.UpgradedNodeLess50Images),
			node:       "laverya-rook-kubernetes-upgrade",
			images:     []string{"doesnotexist", "doesnotexist2"},
			wantImages: []string{"doesnotexist", "doesnotexist2"},
		},
		{
			name:      "a missing node should return an error",
			resources: runtimeFromNodesJSON(testfiles.UpgradedNodeLess50Images),
			node:      "doesnotexist",
			images:    []string{"doesnotexist", "k8s.gcr.io/kube-scheduler:v1.20.15", "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.5.0", "doesnotexist2"},
			wantErr:   true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)
			clientset := fake.NewSimpleClientset(tt.resources...)
			logger := log.New(io.Discard, "", 0)

			gotImages, err := NodeListMissingImages(context.Background(), clientset, logger, tt.node, tt.images, tt.nodeImagesOpts)
			if tt.wantErr {
				req.Error(err)
				return
			}
			req.NoError(err)
			req.ElementsMatch(tt.wantImages, gotImages)
		})
	}
}
