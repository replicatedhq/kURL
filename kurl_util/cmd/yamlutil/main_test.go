package main

import (
	_ "embed"
	"testing"

	"github.com/stretchr/testify/require"
)

//go:embed testfiles/latest.yaml
var latestYaml string

//go:embed testfiles/complex.yaml
var complexYaml string

func Test_jsonField(t *testing.T) {
	tests := []struct {
		name     string
		filePath string
		jsonPath string
		want     string
		wantErr  bool
	}{
		{
			name:     "specific addon from latest",
			filePath: "latest",
			jsonPath: "spec.weave",
			want:     `{"version":"latest"}`,
		},
		{
			name:     "addon that does not exist from latest",
			filePath: "latest",
			jsonPath: "spec.longhorn",
			want:     ``,
			wantErr:  true,
		},
		{
			name:     "multiline strings and quotes",
			filePath: "complex",
			jsonPath: "spec.docker",
			want:     `{"daemonConfig":"this is a test file with newlines\nand quotes\"\nwithin it\n","version":"20.10.5"}`,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)
			testReader := func(path string) []byte {
				if path == "latest" {
					return []byte(latestYaml)
				}
				if path == "complex" {
					return []byte(complexYaml)
				}
				return nil
			}
			got, err := jsonField(testReader, tt.filePath, tt.jsonPath)
			req.Equal(tt.want, got)
			if tt.wantErr {
				req.Error(err)
			} else {
				req.NoError(err)
			}
		})
	}
}

func Test_addFieldToContent(t *testing.T) {
	tests := []struct {
		name        string
		yamlContent string
		yamlPath    string
		value       string
		want        string
	}{
		{
			name: "basic add field",
			yamlContent: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: longhorn
`,
			yamlPath: "metadata_namespace",
			value:    `longhorn`,
			want: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: longhorn
  namespace: longhorn
`,
		},
		{
			name: "basic modify field",
			yamlContent: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: longhorn
`,
			yamlPath: "metadata_name",
			value:    `longhorn-modified`,
			want: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: longhorn-modified
`,
		},
		{
			name: "parent key doesn't exist",
			yamlContent: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
`,
			yamlPath: "metadata_namespace",
			value:    `longhorn`,
			want: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  namespace: longhorn
`,
		},
		{
			name: "add to empty array",
			yamlContent: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: longhorn
spec:
  analyzers: []
  collectors: []
`,
			yamlPath: "spec_collectors[]",
			value: `systemPackages:
  amzn:
  - iscsi-initiator-utils
  - nfs-utils
  centos:
  - iscsi-initiator-utils
  - nfs-utils
  collectorName: longhorn
  ol:
  - iscsi-initiator-utils
  - nfs-utils
  rhel:
  - iscsi-initiator-utils
  - nfs-utils
  ubuntu:
  - open-iscsi
  - nfs-common
`,
			want: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: longhorn
spec:
  analyzers: []
  collectors:
  - systemPackages:
      amzn:
      - iscsi-initiator-utils
      - nfs-utils
      centos:
      - iscsi-initiator-utils
      - nfs-utils
      collectorName: longhorn
      ol:
      - iscsi-initiator-utils
      - nfs-utils
      rhel:
      - iscsi-initiator-utils
      - nfs-utils
      ubuntu:
      - open-iscsi
      - nfs-common
`,
		},
		{
			name: "add to non-empty array",
			yamlContent: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: kurl-builtin
spec:
  collectors:
  - diskUsage:
      collectorName: "Ephemeral Disk Usage /opt/replicated/rook"
      path: /opt/replicated/rook

  analyzers:
  - blockDevices:
      includeUnmountedPartitions: true
      outcomes:
      - pass:
          when: '{{kurl if (and .Installer.Spec.Rook.Version .Installer.Spec.Rook.BlockDeviceFilter) }}{{kurl .Installer.Spec.Rook.BlockDeviceFilter }}{{kurl else }}.*{{kurl end }} == 1'
          message: One available block device
      - pass:
          when: '{{kurl if (and .Installer.Spec.Rook.Version .Installer.Spec.Rook.BlockDeviceFilter) }}{{kurl .Installer.Spec.Rook.BlockDeviceFilter }}{{kurl else }}.*{{kurl end }} > 1'
          message: Multiple available block devices
      - fail:
          message: No available block devices
`,
			yamlPath: "spec_analyzers[]",
			value: `systemPackages:
  collectorName: longhorn
  outcomes:
  - fail:
      message: Package {{ .Name }} is not installed.
      when: '{{ not .IsInstalled }}'
  - pass:
      message: Package {{ .Name }} is installed.`,
			want: `apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: kurl-builtin
spec:
  analyzers:
  - blockDevices:
      includeUnmountedPartitions: true
      outcomes:
      - pass:
          message: One available block device
          when: '{{kurl if (and .Installer.Spec.Rook.Version .Installer.Spec.Rook.BlockDeviceFilter) }}{{kurl .Installer.Spec.Rook.BlockDeviceFilter }}{{kurl else }}.*{{kurl end }} == 1'
      - pass:
          message: Multiple available block devices
          when: '{{kurl if (and .Installer.Spec.Rook.Version .Installer.Spec.Rook.BlockDeviceFilter) }}{{kurl .Installer.Spec.Rook.BlockDeviceFilter }}{{kurl else }}.*{{kurl end }} > 1'
      - fail:
          message: No available block devices
  - systemPackages:
      collectorName: longhorn
      outcomes:
      - fail:
          message: Package {{ .Name }} is not installed.
          when: '{{ not .IsInstalled }}'
      - pass:
          message: Package {{ .Name }} is installed.
  collectors:
  - diskUsage:
      collectorName: Ephemeral Disk Usage /opt/replicated/rook
      path: /opt/replicated/rook
`,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)
			got, err := addFieldToContent([]byte(tt.yamlContent), tt.yamlPath, tt.value)
			req.Equal(tt.want, got)
			req.NoError(err)
		})
	}
}

func Test_removeFieldFromContent(t *testing.T) {
	tests := []struct {
		name        string
		yamlContent string
		yamlPath    string
		want        string
	}{
		{
			name: "basic remove field length 1",
			yamlContent: `apiVersion: v1
kind: ServiceAccount
metadata:
  name: test
  namespace: test
`,
			yamlPath: "metadata",
			want: `apiVersion: v1
kind: ServiceAccount
`,
		},
		{
			name: "basic remove field length 2",
			yamlContent: `apiVersion: v1
kind: ServiceAccount
metadata:
  name: test
  namespace: test
`,
			yamlPath: "metadata_namespace",
			want: `apiVersion: v1
kind: ServiceAccount
metadata:
  name: test
`,
		},
		{
			name: "key doesn't exist length 1",
			yamlContent: `apiVersion: v1
kind: ServiceAccount
`,
			yamlPath: "metadata",
			want: `apiVersion: v1
kind: ServiceAccount
`,
		},
		{
			name: "key doesn't exist length 2",
			yamlContent: `apiVersion: v1
kind: ServiceAccount
metadata:
  name: test
`,
			yamlPath: "metadata_namespace",
			want: `apiVersion: v1
kind: ServiceAccount
metadata:
  name: test
`,
		},
		{
			name: "parent key doesn't exist length 2",
			yamlContent: `apiVersion: v1
kind: ServiceAccount
`,
			yamlPath: "metadata_namespace",
			want: `apiVersion: v1
kind: ServiceAccount
`,
		},
		{
			name: "last child key",
			yamlContent: `apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: test
`,
			yamlPath: "metadata_namespace",
			want: `apiVersion: v1
kind: ServiceAccount
metadata: {}
`,
		},
		{
			name: "multi yaml docs length 1",
			yamlContent: `apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: test
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: test
  name: test
`,
			yamlPath: "metadata",
			want: `apiVersion: v1
kind: ServiceAccount
---
apiVersion: v1
kind: ConfigMap
`,
		},
		{
			name: "multi yaml docs length 2",
			yamlContent: `apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: test
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: test
`,
			yamlPath: "metadata_namespace",
			want: `apiVersion: v1
kind: ServiceAccount
metadata: {}
---
apiVersion: v1
kind: ConfigMap
metadata: {}
`,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)
			got, err := removeFieldFromContent([]byte(tt.yamlContent), tt.yamlPath)
			req.Equal(tt.want, got)
			req.NoError(err)
		})
	}
}
