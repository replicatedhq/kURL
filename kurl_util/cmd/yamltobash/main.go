package main

import (
	"bytes"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"reflect"
	"sort"
	"strconv"
	"strings"

	"github.com/pkg/errors"
	kurlscheme "github.com/replicatedhq/kurl/kurlkinds/client/kurlclientset/scheme"
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	kurlversion "github.com/replicatedhq/kurl/pkg/version"
	"gopkg.in/yaml.v1"
	"k8s.io/client-go/kubernetes/scheme"
)

func getInstallerConfigFromYaml(yamlPath string) (*kurlv1beta1.Installer, map[string]bool, error) {
	yamlData, err := ioutil.ReadFile(yamlPath)
	if err != nil {
		return nil, nil, errors.Wrapf(err, "failed to load file %s", yamlPath)
	}

	yamlData = bytes.TrimSpace(yamlData)
	if len(yamlData) == 0 {
		return nil, nil, nil
	}

	decode := scheme.Codecs.UniversalDeserializer().Decode

	obj, gvk, err := decode(yamlData, nil, nil)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to decode installer yaml")
	}

	if gvk.Group != "cluster.kurl.sh" || gvk.Version != "v1beta1" || gvk.Kind != "Installer" {
		return nil, nil, errors.Errorf("installer yaml contained unepxected gvk: %s/%s/%s", gvk.Group, gvk.Version, gvk.Kind)
	}
	installer := obj.(*kurlv1beta1.Installer)

	fieldsSet, err := getFieldsSet(yamlData)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to get fields set in yaml")
	}

	return installer, fieldsSet, nil
}

func getFieldsSet(yamlDoc []byte) (map[string]bool, error) {
	tmp := map[string]interface{}{}
	if err := yaml.Unmarshal(yamlDoc, tmp); err != nil {
		return nil, err
	}
	specInterface, ok := tmp["spec"]
	if !ok {
		return nil, errors.New("No spec found in yaml")
	}
	specMap, ok := specInterface.(map[interface{}]interface{})
	if !ok {
		return nil, errors.New("Spec is not a map")
	}
	out := map[string]bool{}
	for categoryKeyInterface, categoryInterface := range specMap {
		categoryKey, ok := categoryKeyInterface.(string)
		if !ok {
			continue
		}
		categoryMap, ok := categoryInterface.(map[interface{}]interface{})
		if !ok {
			continue
		}
		for fieldKeyInterface := range categoryMap {
			fieldKey, ok := fieldKeyInterface.(string)
			if !ok {
				continue
			}
			key := fmt.Sprintf("%s.%s", strings.Title(categoryKey), strings.Title(fieldKey))
			out[key] = true
		}
	}

	return out, nil
}

func createMap(retrieved *kurlv1beta1.Installer) map[string]interface{} {
	dictionary := make(map[string]interface{})

	Spec := reflect.ValueOf(retrieved.Spec)

	for i := 0; i < Spec.NumField(); i++ {
		Category := reflect.ValueOf(Spec.Field(i).Interface())

		TypeOfCategory := Category.Type()

		RawCategoryName := Category.String()
		TrimmedRight := strings.Split(RawCategoryName, ".")[1]
		CategoryName := strings.Split(TrimmedRight, " ")[0]

		for i := 0; i < Category.NumField(); i++ {
			if Category.Field(i).CanInterface() {
				dictionary[CategoryName+"."+TypeOfCategory.Field(i).Name] = Category.Field(i).Interface()
			}
		}
	}

	return dictionary
}

func checkIfSkippedVariable(yamlString string) bool {
	skippedVariables := []string{
		"Docker.DaemonConfig",
		"FirewalldConfig.Firewalld",
		"FirewalldConfig.FirewalldCmds",
		"IptablesConfig.IptablesCmds",
		"SelinuxConfig.ChconCmds",
		"SelinuxConfig.Selinux",
		"SelinuxConfig.SemanageCmds",
		"SelinuxConfig.Type"}

	for _, variable := range skippedVariables {
		if variable == yamlString {
			return true
		}
	}
	return false
}

func convertToBash(kurlValues map[string]interface{}, fieldsSet map[string]bool) (map[string]string, error) {
	if kurlValues == nil {
		return nil, errors.New("kurlValues map was nil")
	}

	bashLookup := map[string]string{
		"Calico.Version":                         "CALICO_VERSION",
		"Collectd.Version":                       "COLLECTD_VERSION",
		"CertManager.Version":                    "CERT_MANAGER_VERSION",
		"Containerd.Version":                     "CONTAINERD_VERSION",
		"Contour.TLSMinimumProtocolVersion":      "CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION",
		"Contour.Version":                        "CONTOUR_VERSION",
		"Docker.BypassStorageDriverWarning":      "BYPASS_STORAGEDRIVER_WARNINGS",
		"Docker.DockerRegistryIP":                "DOCKER_REGISTRY_IP",
		"Docker.HardFailOnLoopback":              "HARD_FAIL_ON_LOOPBACK",
		"Docker.NoCEOnEE":                        "NO_CE_ON_EE",
		"Docker.PreserveConfig":                  "PRESERVE_DOCKER_CONFIG",
		"Docker.Version":                         "DOCKER_VERSION",
		"Ekco.MinReadyMasterNodeCount":           "EKCO_MIN_READY_MASTER_NODE_COUNT",
		"Ekco.MinReadyWorkerNodeCount":           "EKCO_MIN_READY_WORKER_NODE_COUNT",
		"Ekco.NodeUnreachableToleration":         "EKCO_NODE_UNREACHABLE_TOLERATION_DURATION",
		"Ekco.RookShouldUseAllNodes":             "EKCO_ROOK_SHOULD_USE_ALL_NODES",
		"Ekco.ShouldDisableRebootServices":       "EKCO_SHOULD_DISABLE_REBOOT_SERVICE",
		"Ekco.ShouldDisableClearNodes":           "EKCO_SHOULD_DISABLE_CLEAR_NODES",
		"Ekco.ShouldEnablePurgeNodes":            "EKCO_SHOULD_ENABLE_PURGE_NODES",
		"Ekco.Version":                           "EKCO_VERSION",
		"FirewalldConfig.BypassFirewalldWarning": "BYPASS_FIREWALLD_WARNING",
		"FirewalldConfig.DisableFirewalld":       "DISABLE_FIREWALLD",
		"FirewalldConfig.HardFailOnFirewalld":    "HARD_FAIL_ON_FIREWALLD",
		"FirewalldConfig.PreserveConfig":         "PRESERVE_FIREWALLD_CONFIG",
		"Fluentd.FullEFKStack":                   "FLUENTD_FULL_EFK_STACK",
		"Fluentd.FluentdConfPath":                "FLUENTD_CONF_FILE",
		"Fluentd.Version":                        "FLUENTD_VERSION",
		"IptablesConfig.PreserveConfig":          "PRESERVE_IPTABLES_CONFIG",
		"Kotsadm.ApplicationNamespace":           "KOTSADM_APPLICATION_NAMESPACES",
		"Kotsadm.ApplicationSlug":                "KOTSADM_APPLICATION_SLUG",
		"Kotsadm.Hostname":                       "KOTSADM_HOSTNAME",
		"Kotsadm.UiBindPort":                     "KOTSADM_UI_BIND_PORT",
		"Kotsadm.Version":                        "KOTSADM_VERSION",
		"Kubernetes.BootstrapToken":              "BOOTSTRAP_TOKEN",
		"Kubernetes.BootstrapTokenTTL":           "BOOTSTRAP_TOKEN_TTL",
		"Kubernetes.CertKey":                     "CERT_KEY",
		"Kubernetes.ControlPlane":                "MASTER",
		"Kubernetes.HACluster":                   "HA_CLUSTER",
		"Kubernetes.KubeadmToken":                "KUBEADM_TOKEN",
		"Kubernetes.KubeadmTokenCAHash":          "KUBEADM_TOKEN_CA_HASH",
		"Kubernetes.LoadBalancerAddress":         "LOAD_BALANCER_ADDRESS",
		"Kubernetes.MasterAddress":               "KUBERNETES_MASTER_ADDR",
		"Kubernetes.UseStandardNodePortRange":    "USE_STANDARD_PORT_RANGE",
		"Kubernetes.ServiceCIDR":                 "SERVICE_CIDR",
		"Kubernetes.ServiceCidrRange":            "SERVICE_CIDR_RANGE",
		"Kubernetes.Version":                     "KUBERNETES_VERSION",
		"Kurl.Airgap":                            "AIRGAP",
		"Kurl.ProxyAddress":                      "PROXY_ADDRESS",
		"Kurl.AdditionalNoProxyAddresses":        "ADDITIONAL_NO_PROXY_ADDRESSES",
		"Kurl.HostnameCheck":                     "HOSTNAME_CHECK",
		"Kurl.NoProxy":                           "NO_PROXY",
		"Kurl.PrivateAddress":                    "PRIVATE_ADDRESS",
		"Kurl.PublicAddress":                     "PUBLIC_ADDRESS",
		"Kurl.Nameserver":                        "NAMESERVER",
		"MetricsServer.Version":                  "METRICS_SERVER_VERSION",
		"Minio.Namespace":                        "MINIO_NAMESPACE",
		"Minio.Version":                          "MINIO_VERSION",
		"OpenEBS.CstorStorageClassName":          "OPENEBS_CSTOR_STORAGE_CLASS",
		"OpenEBS.IsCstorEnabled":                 "OPENEBS_CSTOR",
		"OpenEBS.IsLocalPVEnabled":               "OPENEBS_LOCALPV",
		"OpenEBS.LocalPVStorageClassName":        "OPENEBS_LOCALPV_STORAGE_CLASS",
		"OpenEBS.Namespace":                      "OPENEBS_NAMESPACE",
		"OpenEBS.Version":                        "OPENEBS_VERSION",
		"Prometheus.Version":                     "PROMETHEUS_VERSION",
		"Registry.PublishPort":                   "REGISTRY_PUBLISH_PORT",
		"Registry.Version":                       "REGISTRY_VERSION",
		"Rook.BlockDeviceFilter":                 "ROOK_BLOCK_DEVICE_FILTER",
		"Rook.CephReplicaCount":                  "CEPH_POOL_REPLICAS",
		"Rook.IsBlockStorageEnabled":             "ROOK_BLOCK_STORAGE_ENABLED",
		"Rook.StorageClassName":                  "STORAGE_CLASS",
		"Rook.Version":                           "ROOK_VERSION",
		"SelinuxConfig.DisableSelinux":           "DISABLE_SELINUX",
		"SelinuxConfig.PreserveConfig":           "PRESERVE_SELINUX_CONFIG",
		"Velero.DisableCLI":                      "VELERO_DISABLE_CLI",
		"Velero.DisableRestic":                   "VELERO_DISABLE_RESTIC",
		"Velero.LocalBucket":                     "VELERO_LOCAL_BUCKET",
		"Velero.Namespace":                       "VELERO_LOCAL_BUCKET",
		"Velero.Version":                         "VELERO_VERSION",
		"Weave.IsEncryptionDisabled":             "ENCRYPT_NETWORK",
		"Weave.PodCIDR":                          "POD_CIDR",
		"Weave.PodCidrRange":                     "POD_CIDR_RANGE",
		"Weave.Version":                          "WEAVE_VERSION",
	}

	finalDictionary := make(map[string]string)

	var bashVal string

	for yamlKey, val := range kurlValues {
		if checkIfSkippedVariable(yamlKey) == true {
			//certain variables from the crd are handled by go binaries and not parsed into bash variables
			continue
		}

		bashKey, ok := bashLookup[yamlKey]
		if ok == false {
			return nil, fmt.Errorf("%v not found in lookup table, it has not been added to the lookup table or is not in this version of kurlkinds", yamlKey)
		}

		switch t := interface{}(val).(type) {
		case int:
			if t == 0 {
				bashVal = ""
			} else {
				bashVal = strconv.Itoa(t)
			}
		case string:
			if t == "" {
				bashVal = ""
			} else {
				bashVal = "\"" + t + "\""
			}
		case bool:
			if t == true {
				bashVal = "1"
			} else {
				bashVal = ""
			}
		case []string:
			if len(t) > 0 {
				bashVal = strings.Join(t, ",")
			}
		}

		if yamlKey == "Kubernetes.LoadBalancerAddress" && bashVal != "" {
			finalDictionary["HA_CLUSTER"] = "1"
		}

		if yamlKey == "Kurl.Airgap" && bashVal != "" {
			finalDictionary["OFFLINE_DOCKER_INSTALL"] = "1"
		}

		if yamlKey == "Weave.PodCidrRange" || yamlKey == "Kubernetes.ServiceCidrRange" && bashVal != "" {
			bashVal = strings.Replace(bashVal, "/", "", -1)
		}

		// HARD_FAIL_ON_LOOPBACK defaults to true
		if yamlKey == "Docker.HardFailOnLoopback" && bashVal == "" && !fieldsSet[yamlKey] {
			bashVal = "1"
		}

		finalDictionary[bashKey] = bashVal
	}

	// If preserve and disable flags are set for selinux and firewalld preserve take precedence
	val, _ := finalDictionary["PRESERVE_FIREWALLD_CONFIG"]

	if val == "1" {
		finalDictionary["DISABLE_FIREWALLD"] = ""
	}

	val, _ = finalDictionary["PRESERVE_SELINUX_CONFIG"]

	if val == "1" {
		finalDictionary["DISABLE_SELINUX"] = ""
	}

	return finalDictionary, nil
}

func writeDictionaryToFile(bashDictionary map[string]string, bashPath string) error {
	var variables []string

	for k, v := range bashDictionary {
		variables = append(variables, k+"="+v)
	}

	sort.Strings(variables)

	f, err := os.Create(bashPath)
	if err != nil {
		return errors.Wrap(err, "failed to write bash variables to file")
	}
	defer f.Close()

	for _, value := range variables {
		fmt.Fprintln(f, value) // print values to f, one per line
	}

	return nil
}

func addBashVariablesFromYaml(yamlPath, bashPath string) error {
	installerConfig, fieldsSet, err := getInstallerConfigFromYaml(yamlPath)
	if err != nil {
		return errors.Wrap(err, "failed to load installer yaml")
	}

	yamlDictionary := createMap(installerConfig)

	bashDictionary, err := convertToBash(yamlDictionary, fieldsSet)
	if err != nil {
		return errors.Wrap(err, "failed to convert to bash")
	}

	err = writeDictionaryToFile(bashDictionary, bashPath)
	if err != nil {
		return err
	}

	return nil
}

func main() {
	kurlscheme.AddToScheme(scheme.Scheme)

	version := flag.Bool("v", false, "Print version info")
	installerYAMLPath := flag.String("i", "", "installer YAML for kURL script")
	bashVariablesPath := flag.String("b", "", "the path for the out file of bash variables")

	flag.Parse()

	if *version == true {
		kurlversion.Print()
		return
	}

	if *installerYAMLPath == "" || *bashVariablesPath == "" {
		flag.PrintDefaults()
		os.Exit(-1)
	}

	if err := addBashVariablesFromYaml(*installerYAMLPath, *bashVariablesPath); err != nil {
		log.Fatal(err)
	}
}
