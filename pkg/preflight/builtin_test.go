package preflight

import (
	_ "embed"
	"testing"

	"github.com/itchyny/gojq"
	"github.com/pkg/errors"
	clusterv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/pkg/installer"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	yaml "gopkg.in/yaml.v3"
)

func TestBuiltinExecuteTemplate(t *testing.T) {
	type jsonquery struct {
		query string
		value string
	}
	tests := []struct {
		name      string
		spec      clusterv1beta1.Installer
		isPrimary bool
		isJoin    bool
		isUpgrade bool
		want      []jsonquery
		wantErr   bool
	}{
		{
			name: "basic",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{},
			},
			isPrimary: true,
			want: []jsonquery{
				{
					query: ".spec.collectors[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.analyzers[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.collectors[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"true"`,
				},
			},
		},
		{
			name: "tcpLoadBalancer kubernetes.loadBalancerAddress==1.2.3.4:7443",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{
					Kubernetes: &clusterv1beta1.Kubernetes{
						Version:             "1.19.7",
						LoadBalancerAddress: "1.2.3.4:7443",
					},
				},
			},
			isPrimary: true,
			want: []jsonquery{
				{
					query: ".spec.collectors[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.outcomes",
					value: `- fail:
    message: The load balancer address 1.2.3.4:7443 is not valid.
    when: invalid-address
- warn:
    when: "connection-refused"
    message: Connection to 1.2.3.4:7443 via load balancer was refused.
- warn:
    when: "connection-timeout"
    message: Timed out connecting to 1.2.3.4:7443 via load balancer. Check your firewall.
- warn:
    when: "error"
    message: Unexpected port status
- warn:
    when: "address-in-use"
    message: Port 6443 is unavailable
- pass:
    when: "connected"
    message: Successfully connected to 1.2.3.4:7443 via load balancer
- warn:
    message: Unexpected port status`,
				},
			},
		},
		{
			name: "blockDevices rook.isBlockStorageEnabled==true",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{
					Rook: &clusterv1beta1.Rook{
						Version:               "1.4.3",
						IsBlockStorageEnabled: true,
						BlockDeviceFilter:     "vd[b-z]",
					},
				},
			},
			isPrimary: true,
			want: []jsonquery{
				{
					query: ".spec.collectors[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.outcomes",
					value: `- pass:
    when: "vd[b-z] == 1"
    message: One available block device
- pass:
    when: "vd[b-z] > 1"
    message: Multiple available block devices
- fail:
    message: No available block devices`,
				},
			},
		},
		{
			name: "blockDevices openebs.isCstorEnabled==true",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{
					OpenEBS: &clusterv1beta1.OpenEBS{
						Version:        "1.12.0",
						IsCstorEnabled: true,
					},
				},
			},
			isPrimary: true,
			want: []jsonquery{
				{
					query: ".spec.collectors[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.outcomes",
					value: `- pass:
    when: ".* == 1"
    message: One available block device
- pass:
    when: ".* > 1"
    message: Multiple available block devices
- fail:
    message: No available block devices`,
				},
			},
		},
		{
			name: "join primary",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{
					Kubernetes: &clusterv1beta1.Kubernetes{
						Version:             "1.19.7",
						LoadBalancerAddress: "1.2.3.4:7443",
					},
					Rook: &clusterv1beta1.Rook{
						Version:               "1.4.3",
						IsBlockStorageEnabled: true,
						BlockDeviceFilter:     "vd[b-z]",
					},
				},
			},
			isPrimary: true,
			isJoin:    true,
			want: []jsonquery{
				{
					query: ".spec.collectors[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.analyzers[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.collectors[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.outcomes",
					value: `- pass:
    when: "vd[b-z] == 1"
    message: One available block device
- pass:
    when: "vd[b-z] > 1"
    message: Multiple available block devices
- fail:
    message: No available block devices`,
				},
			},
		},
		{
			name: "join secondary",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{
					Kubernetes: &clusterv1beta1.Kubernetes{
						Version:             "1.19.7",
						LoadBalancerAddress: "1.2.3.4:7443",
					},
					Rook: &clusterv1beta1.Rook{
						Version:               "1.4.3",
						IsBlockStorageEnabled: true,
						BlockDeviceFilter:     "vd[b-z]",
					},
				},
			},
			isJoin: true,
			want: []jsonquery{
				{
					query: ".spec.collectors[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.analyzers[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},

				{
					query: ".spec.collectors[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"false"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.outcomes",
					value: `- pass:
    when: "vd[b-z] == 1"
    message: One available block device
- pass:
    when: "vd[b-z] > 1"
    message: Multiple available block devices
- fail:
    message: No available block devices`,
				},
			},
		},
		{
			name: "upgrade primary",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{
					Kubernetes: &clusterv1beta1.Kubernetes{
						Version:             "1.19.7",
						LoadBalancerAddress: "1.2.3.4:7443",
					},
					Rook: &clusterv1beta1.Rook{
						Version:               "1.4.3",
						IsBlockStorageEnabled: true,
						BlockDeviceFilter:     "vd[b-z]",
					},
				},
			},
			isPrimary: true,
			isUpgrade: true,
			want: []jsonquery{
				{
					query: ".spec.collectors[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.analyzers[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.collectors[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"true"`,
				},
			},
		},
		{
			name: "upgrade secondary",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{
					Kubernetes: &clusterv1beta1.Kubernetes{
						Version:             "1.19.7",
						LoadBalancerAddress: "1.2.3.4:7443",
					},
					Rook: &clusterv1beta1.Rook{
						Version:               "1.4.3",
						IsBlockStorageEnabled: true,
						BlockDeviceFilter:     "vd[b-z]",
					},
				},
			},
			isUpgrade: true,
			want: []jsonquery{
				{
					query: ".spec.collectors[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.analyzers[] | select(.tcpLoadBalancer != null) | .tcpLoadBalancer.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.collectors[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"true"`,
				},
				{
					query: ".spec.analyzers[] | select(.blockDevices != null) | .blockDevices.exclude",
					value: `"true"`,
				},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data := installer.TemplateData{
				Installer: tt.spec,
				IsPrimary: tt.isPrimary,
				IsJoin:    tt.isJoin,
				IsUpgrade: tt.isUpgrade,
			}
			got, err := installer.ExecuteTemplate(tt.name, Builtin(), data)
			if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}

			input := map[string]interface{}{}
			err = yaml.Unmarshal(got, &input)
			require.NoError(t, err)

			for _, q := range tt.want {
				query, err := gojq.Parse(q.query)
				if assert.NoError(t, err) {
					iter := query.Run(input)
					v, ok := iter.Next()
					if !ok {
						assert.NoError(t, errors.New("iterator empty"))
					} else {
						if err, ok := v.(error); ok {
							assert.NoError(t, err)
						} else {
							b, err := yaml.Marshal(v)
							if assert.NoError(t, err) {
								assert.Equal(t, yamlNormalize(t, []byte(q.value)), yamlNormalize(t, b))
							}
						}
					}
				}
			}
		})
	}
}

func yamlNormalize(t *testing.T, y []byte) string {
	var node interface{}
	err := yaml.Unmarshal(y, &node)
	require.NoError(t, err)
	b, err := yaml.Marshal(node)
	require.NoError(t, err)
	return string(b)
}
