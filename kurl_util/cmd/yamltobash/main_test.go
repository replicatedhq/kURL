package main

import (
	"os"
	"path"
	"reflect"
	"testing"

	kurlscheme "github.com/replicatedhq/kurlkinds/client/kurlclientset/scheme"
	kurlv1beta1 "github.com/replicatedhq/kurlkinds/pkg/apis/cluster/v1beta1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/kubernetes/scheme"
)

func Test_convertToBash(t *testing.T) {
	tests := []struct {
		name      string
		inputMap  map[string]interface{}
		fieldsSet map[string]bool
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
		{
			name: "CertManager.Version sets CERT_MANAGER_VERSION",
			inputMap: map[string]interface{}{
				"CertManager.Version": "1.0.3",
			},
			wantedMap: map[string]string{
				"CERT_MANAGER_VERSION": `"1.0.3"`,
			},
			wantError: false,
		},
		{
			name: "MetricsServer.Version sets METRICS_SERVER_VERSION",
			inputMap: map[string]interface{}{
				"MetricsServer.Version": "0.3.7",
			},
			wantedMap: map[string]string{
				"METRICS_SERVER_VERSION": `"0.3.7"`,
			},
		},
		{
			name: "Docker.HardFailOnLoopback defaults to true",
			inputMap: map[string]interface{}{
				"Docker.HardFailOnLoopback": false,
			},
			wantedMap: map[string]string{
				"HARD_FAIL_ON_LOOPBACK": "1",
			},
		},
		{
			name: "Docker.HardFailOnLoopback can be explicitly set to false",
			inputMap: map[string]interface{}{
				"Docker.HardFailOnLoopback": false,
			},
			fieldsSet: map[string]bool{
				"Docker.HardFailOnLoopback": true,
			},
			wantedMap: map[string]string{
				"HARD_FAIL_ON_LOOPBACK": "",
			},
		},
		{
			name: "Docker.HardFailOnLoopback can be explicitly set to true",
			inputMap: map[string]interface{}{
				"Docker.HardFailOnLoopback": true,
			},
			fieldsSet: map[string]bool{
				"Docker.HardFailOnLoopback": true,
			},
			wantedMap: map[string]string{
				"HARD_FAIL_ON_LOOPBACK": "1",
			},
		},
		{
			name: "Antrea.Encryption",
			inputMap: map[string]interface{}{
				"Antrea.IsEncryptionDisabled": true,
			},
			wantedMap: map[string]string{
				"ANTREA_DISABLE_ENCRYPTION": "1",
			},
		},
		{
			name: "Sonobuoy.Version sets SONOBUOY_VERSION",
			inputMap: map[string]interface{}{
				"Sonobuoy.Version": "0.50.0",
			},
			wantedMap: map[string]string{
				"SONOBUOY_VERSION": `"0.50.0"`,
			},
		},
		{
			name: "Sonobuoy.S3Override sets SONOBUOY_S3_OVERRIDE",
			inputMap: map[string]interface{}{
				"Sonobuoy.S3Override": "https://kurl-sh.s3.amazonaws.com/pr/2000-1111111-sonobuoy-0.50.0.tar.gz",
			},
			wantedMap: map[string]string{
				"SONOBUOY_S3_OVERRIDE": `"https://kurl-sh.s3.amazonaws.com/pr/2000-1111111-sonobuoy-0.50.0.tar.gz"`,
			},
		},
		{
			name: "Rook.BypassUpgradeWarning sets ROOK_BYPASS_UPGRADE_WARNING",
			inputMap: map[string]interface{}{
				"Rook.BypassUpgradeWarning": true,
			},
			wantedMap: map[string]string{
				"ROOK_BYPASS_UPGRADE_WARNING": `1`,
			},
		},
		{
			name: "RKE2.Version",
			inputMap: map[string]interface{}{
				"RKE2.Version": "v1.19.7+rke2r1",
			},
			wantedMap: map[string]string{},
			wantError: false,
		},
		{
			name: "K3S.Version",
			inputMap: map[string]interface{}{
				"K3S.Version": "v1.19.7+rke2r1",
			},
			wantedMap: map[string]string{},
			wantError: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			req := require.New(t)

			outputMap, err := convertToBash(test.inputMap, test.fieldsSet)
			if test.wantError {
				req.Error(err)
			} else {
				req.NoError(err)
			}

			assert.Equal(t, test.wantedMap, outputMap)
		})
	}
}

func TestGetFieldsSet(t *testing.T) {
	tests := []struct {
		name   string
		yaml   string
		expect map[string]bool
	}{
		{
			name: "Docker.HardFailOnLoopback",
			yaml: `apiVersion: cluster.kurl.sh/v1beta
kind: Installer
metadata:
  name: kurl
spec:
  kubernetes:
    version: 1.19.3
  docker:
    version: 19.03.10
    hardFailOnLoopback: false
  weave:
    version: 2.6.5`,
			expect: map[string]bool{
				"Kubernetes.Version":        true,
				"Docker.Version":            true,
				"Docker.HardFailOnLoopback": true,
				"Weave.Version":             true,
			},
		},
		{
			name: "Antrea.IsEncryptionDisabled",
			yaml: `apiVersion: cluster.kurl.sh/v1beta
kind: Installer
metadata:
  name: kurl
spec:
  kubernetes:
    version: 1.19.3
  docker:
    version: 19.03.10
  antrea:
    isEncryptionDisabled: true
    version: 0.13.1`,
			expect: map[string]bool{
				"Kubernetes.Version":          true,
				"Docker.Version":              true,
				"Antrea.Version":              true,
				"Antrea.IsEncryptionDisabled": true,
			},
		}, {
			name: "Docker.LicenseFile",
			yaml: `apiVersion: cluster.kurl.sh/v1beta
kind: Installer
metadata:
  name: kurl
spec:
  kurl:
    licenseURL: hello.com
  kubernetes:
    version: 1.19.3
    cisCompliance: true
    clusterName: mycluster
  docker:
    version: 19.03.10
    hardFailOnLoopback: false
  weave:
    version: 2.6.5`,
			expect: map[string]bool{
				"Kubernetes.Version":        true,
				"Docker.Version":            true,
				"Docker.HardFailOnLoopback": true,
				"Weave.Version":             true,
				"Kurl.LicenseURL":           true,
				"Kubernetes.CisCompliance":  true,
				"Kubernetes.ClusterName":    true,
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			out, err := getFieldsSet([]byte(test.yaml))
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(out, test.expect) {
				t.Errorf("Expected %+v\ngot %+v", test.expect, out)
			}
		})
	}
}

func Test_createMap(t *testing.T) {
	tests := []struct {
		name      string
		retrieved *kurlv1beta1.Installer
		want      map[string]interface{}
	}{
		{
			name: "basic",
			retrieved: &kurlv1beta1.Installer{
				Spec: kurlv1beta1.InstallerSpec{
					Kubernetes: &kurlv1beta1.Kubernetes{
						S3Override: "BLAH",
					},
				},
			},
			want: map[string]interface{}{
				"Kubernetes.S3Override": "BLAH",
			},
		}, {
			name: "kurl.",
			retrieved: &kurlv1beta1.Installer{
				Spec: kurlv1beta1.InstallerSpec{
					Kurl: &kurlv1beta1.Kurl{
						LicenseURL: "example.com/license/example-license.txt",
					},
				},
			},
			want: map[string]interface{}{
				"Kurl.LicenseURL": "example.com/license/example-license.txt",
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := createMap(tt.retrieved)
			for k, v := range tt.want {
				if !reflect.DeepEqual(got[k], v) {
					t.Errorf("createMap()[%s] = %v, want %v", k, got[k], v)
				}
			}
		})
	}
}

func TestEndToEnd(t *testing.T) {
	tt := []struct {
		name           string
		yaml           string
		expectedRegexp string
		wantErr        bool
	}{
		{
			name:           "default weave masq should be set",
			yaml:           "weave_no_masq_local_default.yaml",
			expectedRegexp: "(?m)^NO_MASQ_LOCAL=1$",
		},
		{
			name:           "weave masq should be set",
			yaml:           "weave_no_masq_local_set.yaml",
			expectedRegexp: "(?m)^NO_MASQ_LOCAL=1$",
		},
		{
			name:           "weave masq should not be set",
			yaml:           "weave_no_masq_local_unset.yaml",
			expectedRegexp: "(?m)^NO_MASQ_LOCAL=0$",
		},
	}

	utilruntime.Must(kurlscheme.AddToScheme(scheme.Scheme))

	for _, tc := range tt {
		t.Run(tc.name, func(t *testing.T) {
			envPath := path.Join(t.TempDir(), "out")
			yamlPath := path.Join("testdata", "yaml", tc.yaml)
			err := addBashVariablesFromYaml(yamlPath, envPath)
			if tc.wantErr {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			b, err := os.ReadFile(envPath)
			require.NoError(t, err)
			actual := string(b)
			require.Regexp(t, tc.expectedRegexp, actual)
		})
	}
}
