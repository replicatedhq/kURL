package cluster

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/replicatedhq/kurl/pkg/rook/testfiles"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
)

// test function only, contains panics
func runtimeFromNodesJson(nodeListJson []byte) []runtime.Object {
	podList := corev1.NodeList{}
	err := json.Unmarshal(nodeListJson, &podList)
	if err != nil {
		panic(err) // this is only called for unit tests, not at runtime
	}

	runtimeObjects := []runtime.Object{}
	for idx, _ := range podList.Items {
		runtimeObjects = append(runtimeObjects, &podList.Items[idx])
	}
	return runtimeObjects
}

func Test_countRookOSDs(t *testing.T) {
	tests := []struct {
		name      string
		resources []runtime.Object
		images    []string
		wantNodes []string
	}{
		{
			name:      "an image that does not exist should return the node",
			resources: runtimeFromNodesJson(testfiles.UpgradedNode),
			images:    []string{"doesnotexist"},
			wantNodes: []string{"laverya-rook-kubernetes-upgrade"},
		},
		{
			name:      "an image that does exist should not return the node",
			resources: runtimeFromNodesJson(testfiles.UpgradedNode),
			images:    []string{"registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.5.0"},
			wantNodes: []string{},
		},
		{
			name:      "an image that does exist and one that does should return the node",
			resources: runtimeFromNodesJson(testfiles.UpgradedNode),
			images:    []string{"registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.5.0", "doesnotexist"},
			wantNodes: []string{"laverya-rook-kubernetes-upgrade"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)
			clientset := fake.NewSimpleClientset(tt.resources...)

			gotNodes, err := NodesMissingImages(context.Background(), clientset, tt.images)
			req.NoError(err)
			req.ElementsMatch(tt.wantNodes, gotNodes)
		})
	}
}
