package main

import (
	"testing"
	// "reflect"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_convertToBash(t *testing.T) {
	tests := []struct {
		name      string
		inputMap  map[string]interface{}
		wantedMap map[string]string
		wantError bool
	}{
		{
			name:      "errors if inputMap is empty",
			inputMap:  nil,
			wantedMap: nil,
			wantError: true,
		},
		{
			name: "errors if inputMap is has key not part of installer spec",
			inputMap: map[string]interface{}{
				"BAD_KEY": "latest",
			},
			wantedMap: nil,
			wantError: true,
		},
		{
			name: "ignores variables handled by other go binaries",
			inputMap: map[string]interface{}{
				"Contour.Version":     "latest",
				"Docker.DaemonConfig": "some_config",
			},
			wantedMap: map[string]string{
				"CONTOUR_VERSION": "\"latest\"",
			},
			wantError: false,
		},
		{
			name: "convertToBash parses ints, bool, and strings properly",
			inputMap: map[string]interface{}{
				"Contour.Version":        "latest",
				"Rook.CephReplicaCount":  4,
				"OpenEBS.IsCstorEnabled": true,
			},
			wantedMap: map[string]string{
				"CEPH_POOL_REPLICAS": "4",
				"CONTOUR_VERSION":    "\"latest\"",
				"OPENEBS_CSTOR":      "1",
			},
			wantError: false,
		},
		{
			name: "Kurl.Airgap and Kubernetes.LoadBalancerAddress expand to multiple values",
			inputMap: map[string]interface{}{
				"Kurl.Airgap":                    true,
				"Kubernetes.LoadBalancerAddress": "192.168.1.1",
			},
			wantedMap: map[string]string{
				"LOAD_BALANCER_ADDRESS":  "\"192.168.1.1\"",
				"AIRGAP":                 "1",
				"HA_CLUSTER":             "1",
				"NO_PROXY":               "1",
				"OFFLINE_DOCKER_INSTALL": "1",
			},
			wantError: false,
		},
		{
			name: "Weave.PodCidrRange and Kubernetes.ServiceCidrRange will truncate a '/'",
			inputMap: map[string]interface{}{
				"Weave.PodCidrRange":          "/24",
				"Kubernetes.ServiceCidrRange": "16",
			},
			wantedMap: map[string]string{
				"SERVICE_CIDR_RANGE": "\"16\"",
				"POD_CIDR_RANGE":     "\"24\"",
			},
			wantError: false,
		},
		{
			name: "SelinuxConfig.PreserveConfig and FirewalldConfig.PreserveConfig override SelinuxConfig.DisableSelinuxConfig and FirewalldConfig.DisableFirewalldConfig",
			inputMap: map[string]interface{}{
				"FirewalldConfig.DisableFirewalld": true,
				"FirewalldConfig.PreserveConfig":   true,
				"SelinuxConfig.DisableSelinux":     true,
				"SelinuxConfig.PreserveConfig":     true,
			},
			wantedMap: map[string]string{
				"PRESERVE_FIREWALLD_CONFIG": "1",
				"PRESERVE_SELINUX_CONFIG":   "1",
				"DISABLE_FIREWALLD":         "",
				"DISABLE_SELINUX":           "",
			},
			wantError: false,
		},
		{
			name: "Kurl.AdditionalNoProxyAddresses is joined with commas",
			inputMap: map[string]interface{}{
				"Kurl.AdditionalNoProxyAddresses": []string{"10.128.0.3", "10.128.0.4", "10.138.0.0/16", "registry.internal"},
			},
			wantedMap: map[string]string{
				"ADDITIONAL_NO_PROXY_ADDRESSES": "10.128.0.3,10.128.0.4,10.138.0.0/16,registry.internal",
			},
			wantError: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			req := require.New(t)

			outputMap, err := convertToBash(test.inputMap)
			if test.wantError {
				req.Error(err)
			} else {
				req.NoError(err)
			}

			assert.Equal(t, test.wantedMap, outputMap)
		})
	}
}
