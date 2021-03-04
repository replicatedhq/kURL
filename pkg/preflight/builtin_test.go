package preflight

import (
	_ "embed"
	"testing"

	clusterv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/replicatedhq/kurl/pkg/installer"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBuiltinExecuteTemplate(t *testing.T) {
	tests := []struct {
		name      string
		spec      clusterv1beta1.Installer
		isPrimary bool
		isJoin    bool
		isUpgrade bool
		want      string
		wantErr   bool
	}{
		{
			name: "basic",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{},
			},
			isPrimary: true,
			want: `# https://kurl.sh/docs/install-with-kurl/system-requirements
apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: kurl-builtin
spec:
  collectors:
    - cpu: {}
    - memory: {}
    - diskUsage:
        collectorName: "Ephemeral Disk Usage"
        path: /var/lib/kubelet
    - tcpLoadBalancer:
        collectorName: "Kubernetes API Server Load Balancer"
        port: 6443
        address: 
        timeout: 3m
        exclude: 'true'
  analyzers:
    - cpu:
        checkName: "Number of CPUs"
        outcomes:
          - warn:
              when: "count < 4"
              message: At least 4 CPU cores are recommended
          - fail:
              when: "count < 2"
              message: At least 2 CPU cores are required
          - pass:
              message: This server has at least 4 CPU cores
    - memory:
        checkName: "Amount of Memory"
        outcomes:
          - warn:
              when: "< 8Gi"
              message: At least 8Gi of memory is recommended
          - fail:
              when: "< 4Gi"
              message: At least 4Gi of memory is required, and 8Gi of memory is recommended
          - pass:
              message: The system has at least 8Gi of memory
    - diskUsage:
        checkName: "Ephemeral Disk Usage"
        collectorName: "Ephemeral Disk Usage"
        outcomes:
          - fail:
              when: "total < 30Gi"
              message: The disk containing directory /var/lib/kubelet has less than 30Gi of total space
          - fail:
              when: "used/total > 80%"
              message: The disk containing directory /var/lib/kubelet is more than 80% full
          - warn:
              when: "used/total > 60%"
              message: The disk containing directory /var/lib/kubelet is more than 60% full
          - pass:
              message: The disk containing directory /var/lib/kubelet has at least 30Gi disk space available
    - tcpLoadBalancer:
        checkName: "Kubernetes API Server Load Balancer"
        collectorName: "Kubernetes API Server Load Balancer"
        exclude: 'true'
        outcomes:
          - warn:
              when: "connection-refused"
              message: Connection to  via load balancer was refused.
          - warn:
              when: "connection-timeout"
              message: Timed out connecting to  via load balancer. Check your firewall.
          - warn:
              when: "error"
              message: Unexpected port status
          - warn:
              when: "address-in-use"
              message: Port 6443 is unavailable
          - pass:
              when: "connected"
              message: Successfully connected to  via load balancer
          - warn:
              message: Unexpected port status
`,
		},
		{
			name: "load balancer",
			spec: clusterv1beta1.Installer{
				Spec: clusterv1beta1.InstallerSpec{
					Kubernetes: clusterv1beta1.Kubernetes{
						LoadBalancerAddress: "1.2.3.4:7443",
					},
				},
			},
			isPrimary: true,
			want: `# https://kurl.sh/docs/install-with-kurl/system-requirements
apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: kurl-builtin
spec:
  collectors:
    - cpu: {}
    - memory: {}
    - diskUsage:
        collectorName: "Ephemeral Disk Usage"
        path: /var/lib/kubelet
    - tcpLoadBalancer:
        collectorName: "Kubernetes API Server Load Balancer"
        port: 6443
        address: 1.2.3.4:7443
        timeout: 3m
        exclude: 'false'
  analyzers:
    - cpu:
        checkName: "Number of CPUs"
        outcomes:
          - warn:
              when: "count < 4"
              message: At least 4 CPU cores are recommended
          - fail:
              when: "count < 2"
              message: At least 2 CPU cores are required
          - pass:
              message: This server has at least 4 CPU cores
    - memory:
        checkName: "Amount of Memory"
        outcomes:
          - warn:
              when: "< 8Gi"
              message: At least 8Gi of memory is recommended
          - fail:
              when: "< 4Gi"
              message: At least 4Gi of memory is required
          - pass:
              message: The system has at least 8Gi of memory
    - diskUsage:
        checkName: "Ephemeral Disk Usage"
        collectorName: "Ephemeral Disk Usage"
        outcomes:
          - fail:
              when: "total < 30Gi"
              message: The disk containing directory /var/lib/kubelet has less than 30Gi of total space
          - fail:
              when: "used/total > 80%"
              message: The disk containing directory /var/lib/kubelet is more than 80% full
          - warn:
              when: "used/total > 60%"
              message: The disk containing directory /var/lib/kubelet is more than 60% full
          - pass:
              message: The disk containing directory /var/lib/kubelet has at least 30Gi disk space available
    - tcpLoadBalancer:
        checkName: "Kubernetes API Server Load Balancer"
        collectorName: "Kubernetes API Server Load Balancer"
        exclude: 'false'
        outcomes:
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
              message: Unexpected port status
`,
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
			assert.Equal(t, tt.want, string(got))
		})
	}
}
