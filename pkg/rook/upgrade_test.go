package rook

import (
	"encoding/json"
	"testing"

	"github.com/replicatedhq/kurl/pkg/rook/testfiles"
	"github.com/stretchr/testify/assert"
	appsv1 "k8s.io/api/apps/v1"
)

func Test_normalizeRookVersion(t *testing.T) {
	type args struct {
		v string
	}
	tests := []struct {
		name string
		args args
		want string
	}{
		{
			name: "v1.4.6",
			args: args{
				v: "v1.4.6",
			},
			want: "1.4.6",
		},
		{
			name: "1.4.6",
			args: args{
				v: "1.4.6",
			},
			want: "1.4.6",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := normalizeRookVersion(tt.args.v); got != tt.want {
				t.Errorf("normalizeRookVersion() = %v, want %v", got, tt.want)
			}
		})
	}
}

// test function only, contains panics
func deploymentListFromDeploymentsJson(nodeListJson []byte) appsv1.DeploymentList {
	deploymentList := appsv1.DeploymentList{}
	err := json.Unmarshal(nodeListJson, &deploymentList)
	if err != nil {
		panic(err) // this is only called for unit tests, not at runtime
	}
	return deploymentList
}

func Test_hasRookOrCephVersion(t *testing.T) {
	type args struct {
		desiredVersion string
		labelKey       string
	}
	tests := []struct {
		name           string
		deploymentList appsv1.DeploymentList
		args           args
		wantOk         bool
		wantMessages   []string
	}{
		{
			name:           "all rook versions up to date",
			deploymentList: deploymentListFromDeploymentsJson(testfiles.WaitForRookVersionAllReady),
			args: args{
				desiredVersion: "1.8.10",
				labelKey:       "rook-version",
			},
			wantOk: true,
		},
		{
			name:           "old versions",
			deploymentList: deploymentListFromDeploymentsJson(testfiles.WaitForRookVersionOldVersions),
			args: args{
				desiredVersion: "1.8.10",
				labelKey:       "rook-version",
			},
			wantOk:       false,
			wantMessages: []string{"deployments rook-ceph-osd-3, rook-ceph-osd-4 still running 1.7.11"},
		},
		{
			name:           "not ready",
			deploymentList: deploymentListFromDeploymentsJson(testfiles.WaitForRookVersionNotReady),
			args: args{
				desiredVersion: "1.8.10",
				labelKey:       "rook-version",
			},
			wantOk:       false,
			wantMessages: []string{"deployments rook-ceph-mds-rook-shared-fs-a, rook-ceph-mds-rook-shared-fs-b not ready"},
		},
		{
			name:           "with ceph version empty",
			deploymentList: deploymentListFromDeploymentsJson(testfiles.WaitForRookVersionAllReadyWithEmptyVersion),
			args: args{
				desiredVersion: "16.2.9-0",
				labelKey:       "ceph-version",
			},
			wantOk: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ass := assert.New(t)
			ok, messages := hasRookOrCephVersion(&tt.deploymentList, tt.args.desiredVersion, tt.args.labelKey)
			ass.Equal(tt.wantOk, ok)
			ass.Equal(tt.wantMessages, messages)
		})
	}
}
