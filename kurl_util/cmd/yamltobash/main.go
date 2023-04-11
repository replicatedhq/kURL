package main

import (
	"bytes"
	"flag"
	"fmt"
	"log"
	"os"
	"reflect"
	"sort"
	"strconv"
	"strings"

	"github.com/pkg/errors"
	kurlversion "github.com/replicatedhq/kurl/pkg/version"
	kurlscheme "github.com/replicatedhq/kurlkinds/client/kurlclientset/scheme"
	kurlv1beta1 "github.com/replicatedhq/kurlkinds/pkg/apis/cluster/v1beta1"
	"golang.org/x/text/cases"
	"golang.org/x/text/language"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/kubernetes/scheme"
)

func getInstallerConfigFromYaml(yamlPath string) (*kurlv1beta1.Installer, map[string]bool, error) {
	yamlData, err := os.ReadFile(yamlPath)
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
			caser := cases.Title(language.English, cases.NoLower)
			key := fmt.Sprintf("%s.%s", caser.String(categoryKey), caser.String(fieldKey))
			out[key] = true
		}
	}

	return out, nil
}

func createMap(retrieved *kurlv1beta1.Installer) map[string]interface{} {
	dictionary := make(map[string]interface{})

	Spec := reflect.ValueOf(retrieved.Spec)

	for i := 0; i < Spec.NumField(); i++ {
		var Category reflect.Value
		if Spec.Field(i).Kind() == reflect.Ptr {
			if Spec.Field(i).IsNil() {
				ptr := reflect.New(Spec.Field(i).Type()).Elem()
				Category = reflect.ValueOf(reflect.New(ptr.Type().Elem()).Elem().Interface())
			} else {
				Category = reflect.ValueOf(Spec.Field(i).Elem().Interface())
			}
		} else {
			Category = reflect.ValueOf(Spec.Field(i).Interface())
		}

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
		"Kurl.InstallerVersion",
		"SelinuxConfig.ChconCmds",
		"SelinuxConfig.Selinux",
		"SelinuxConfig.SemanageCmds",
		"SelinuxConfig.Type",
		"K3S.Version",  // removed support for k3s
		"RKE2.Version", // removed support for rke2
	}

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
		"Calico.S3Override":                               "CALICO_S3_OVERRIDE",
		"Calico.Version":                                  "CALICO_VERSION",
		"Collectd.S3Override":                             "COLLECTD_S3_OVERRIDE",
		"Collectd.Version":                                "COLLECTD_VERSION",
		"CertManager.S3Override":                          "CERT_MANAGER_S3_OVERRIDE",
		"CertManager.Version":                             "CERT_MANAGER_VERSION",
		"Containerd.PreserveConfig":                       "CONTAINERD_PRESERVE_CONFIG",
		"Containerd.TomlConfig":                           "CONTAINERD_TOML_CONFIG",
		"Containerd.S3Override":                           "CONTAINERD_S3_OVERRIDE",
		"Containerd.Version":                              "CONTAINERD_VERSION",
		"Contour.HTTPPort":                                "CONTOUR_HTTP_PORT",
		"Contour.HTTPSPort":                               "CONTOUR_HTTPS_PORT",
		"Contour.S3Override":                              "CONTOUR_S3_OVERRIDE",
		"Contour.TLSMinimumProtocolVersion":               "CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION",
		"Contour.Version":                                 "CONTOUR_VERSION",
		"Docker.BypassStorageDriverWarning":               "BYPASS_STORAGEDRIVER_WARNINGS",
		"Docker.DockerRegistryIP":                         "DOCKER_REGISTRY_IP",
		"Docker.HardFailOnLoopback":                       "HARD_FAIL_ON_LOOPBACK",
		"Docker.NoCEOnEE":                                 "NO_CE_ON_EE",
		"Docker.PreserveConfig":                           "PRESERVE_DOCKER_CONFIG",
		"Docker.S3Override":                               "DOCKER_S3_OVERRRIDE",
		"Docker.Version":                                  "DOCKER_VERSION",
		"Ekco.MinReadyMasterNodeCount":                    "EKCO_MIN_READY_MASTER_NODE_COUNT",
		"Ekco.MinReadyWorkerNodeCount":                    "EKCO_MIN_READY_WORKER_NODE_COUNT",
		"Ekco.NodeUnreachableToleration":                  "EKCO_NODE_UNREACHABLE_TOLERATION_DURATION",
		"Ekco.RookShouldUseAllNodes":                      "EKCO_ROOK_SHOULD_USE_ALL_NODES",
		"Ekco.RookShouldDisableReconcileMDSPlacement":     "EKCO_ROOK_SHOULD_DISABLE_RECONCILE_MDS_PLACEMENT",
		"Ekco.RookShouldDisableReconcileCephCSIResources": "EKCO_ROOK_SHOULD_DISABLE_RECONCILE_CEPH_CSI_RESOURCES",
		"Ekco.S3Override":                                 "EKCO_S3_OVERRIDE",
		"Ekco.ShouldDisableRebootServices":                "EKCO_SHOULD_DISABLE_REBOOT_SERVICE",
		"Ekco.ShouldDisableClearNodes":                    "EKCO_SHOULD_DISABLE_CLEAR_NODES",
		"Ekco.ShouldEnablePurgeNodes":                     "EKCO_SHOULD_ENABLE_PURGE_NODES",
		"Ekco.Version":                                    "EKCO_VERSION",
		"Ekco.AutoUpgradeSchedule":                        "EKCO_AUTO_UPGRADE_SCHEDULE", // no longer supported
		"Ekco.EnableInternalLoadBalancer":                 "EKCO_ENABLE_INTERNAL_LOAD_BALANCER",
		"Ekco.PodImageOverrides":                          "EKCO_POD_IMAGE_OVERRIDES",
		"Ekco.ShouldDisableRestartFailedEnvoyPods":        "EKCO_SHOULD_DISABLE_RESTART_FAILED_ENVOY_PODS",
		"Ekco.EnvoyPodsNotReadyDuration":                  "EKCO_ENVOY_PODS_NOT_READY_DURATION",
		"Ekco.MinioShouldDisableManagement":               "EKCO_MINIO_SHOULD_DISABLE_MANAGEMENT",
		"Ekco.KotsadmShouldDisableManagement":             "EKCO_KOTSADM_SHOULD_DISABLE_MANAGEMENT",
		"FirewalldConfig.BypassFirewalldWarning":          "BYPASS_FIREWALLD_WARNING",
		"FirewalldConfig.DisableFirewalld":                "DISABLE_FIREWALLD",
		"FirewalldConfig.HardFailOnFirewalld":             "HARD_FAIL_ON_FIREWALLD",
		"FirewalldConfig.PreserveConfig":                  "PRESERVE_FIREWALLD_CONFIG",
		"Fluentd.FullEFKStack":                            "FLUENTD_FULL_EFK_STACK",
		"Fluentd.FluentdConfPath":                         "FLUENTD_CONF_FILE",
		"Fluentd.S3Override":                              "FLUENTD_S3_OVERRIDE",
		"Fluentd.Version":                                 "FLUENTD_VERSION",
		"Helm.AdditionalImages":                           "HELM_ADDITIONAL_IMAGES",
		"Helm.HelmfileSpec":                               "HELM_HELMFILE_SPEC",
		"IptablesConfig.PreserveConfig":                   "PRESERVE_IPTABLES_CONFIG",
		"Kotsadm.ApplicationNamespace":                    "KOTSADM_APPLICATION_NAMESPACES",
		"Kotsadm.ApplicationSlug":                         "KOTSADM_APPLICATION_SLUG",
		"Kotsadm.ApplicationVersionLabel":                 "KOTSADM_APPLICATION_VERSION_LABEL",
		"Kotsadm.Hostname":                                "KOTSADM_HOSTNAME",
		"Kotsadm.S3Override":                              "KOTSADM_S3_OVERRIDE",
		"Kotsadm.DisableS3":                               "KOTSADM_DISABLE_S3",
		"Kotsadm.UiBindPort":                              "KOTSADM_UI_BIND_PORT",
		"Kotsadm.Version":                                 "KOTSADM_VERSION",
		"Kubernetes.BootstrapToken":                       "BOOTSTRAP_TOKEN",
		"Kubernetes.BootstrapTokenTTL":                    "BOOTSTRAP_TOKEN_TTL",
		"Kubernetes.CertKey":                              "CERT_KEY",
		"Kubernetes.CisCompliance":                        "KUBERNETES_CIS_COMPLIANCE",
		"Kubernetes.ClusterName":                          "KUBERNETES_CLUSTER_NAME",
		"Kubernetes.ControlPlane":                         "MASTER",
		"Kubernetes.ContainerLogMaxSize":                  "CONTAINER_LOG_MAX_SIZE",
		"Kubernetes.ContainerLogMaxFiles":                 "CONTAINER_LOG_MAX_FILES",
		"Kubernetes.MaxPodsPerNode":                       "KUBERNETES_MAX_PODS_PER_NODE",
		"Kubernetes.EvictionThresholdResources":           "EVICTION_THRESHOLD",
		"Kubernetes.HACluster":                            "HA_CLUSTER",
		"Kubernetes.KubeadmToken":                         "KUBEADM_TOKEN",
		"Kubernetes.KubeadmTokenCAHash":                   "KUBEADM_TOKEN_CA_HASH",
		"Kubernetes.KubeReserved":                         "KUBE_RESERVED",
		"Kubernetes.LoadBalancerAddress":                  "LOAD_BALANCER_ADDRESS",
		"Kubernetes.LoadBalancerUseFirstPrimary":          "KUBERNETES_LOAD_BALANCER_USE_FIRST_PRIMARY",
		"Kubernetes.MasterAddress":                        "KUBERNETES_MASTER_ADDR",
		"Kubernetes.S3Override":                           "SERVICE_S3_OVERRIDE",
		"Kubernetes.ServiceCIDR":                          "SERVICE_CIDR",
		"Kubernetes.ServiceCidrRange":                     "SERVICE_CIDR_RANGE",
		"Kubernetes.SystemReservedResources":              "SYSTEM_RESERVED",
		"Kubernetes.UseStandardNodePortRange":             "USE_STANDARD_PORT_RANGE",
		"Kubernetes.Version":                              "KUBERNETES_VERSION",
		"Kubernetes.InitIgnorePreflightErrors":            "KUBERNETES_INIT_IGNORE_PREFLIGHT_ERRORS",
		"Kubernetes.UpgradeIgnorePreflightErrors":         "KUBERNETES_UPGRADE_IGNORE_PREFLIGHT_ERRORS",
		"Kurl.AdditionalNoProxyAddresses":                 "ADDITIONAL_NO_PROXY_ADDRESSES",
		"Kurl.Airgap":                                     "AIRGAP",
		"Kurl.IPv6":                                       "IPV6_ONLY",
		"Kurl.LicenseURL":                                 "LICENSE_URL",
		"Kurl.HostnameCheck":                              "HOSTNAME_CHECK",
		"Kurl.IgnoreRemoteLoadImagesPrompt":               "KURL_IGNORE_REMOTE_LOAD_IMAGES_PROMPT",
		"Kurl.IgnoreRemoteUpgradePrompt":                  "KURL_IGNORE_REMOTE_UPGRADE_PROMPT",
		"Kurl.Nameserver":                                 "NAMESERVER",
		"Kurl.NoProxy":                                    "NO_PROXY",
		"Kurl.HostPreflights":                             "HOST_PREFLIGHTS",
		"Kurl.HostPreflightIgnore":                        "HOST_PREFLIGHT_IGNORE",
		"Kurl.HostPreflightEnforceWarnings":               "HOST_PREFLIGHT_ENFORCE_WARNINGS",
		"Kurl.PrivateAddress":                             "PRIVATE_ADDRESS",
		"Kurl.ProxyAddress":                               "PROXY_ADDRESS",
		"Kurl.PublicAddress":                              "PUBLIC_ADDRESS",
		"Kurl.SkipSystemPackageInstall":                   "SKIP_SYSTEM_PACKAGE_INSTALL",
		"Kurl.ExcludeBuiltinHostPreflights":               "EXCLUDE_BUILTIN_HOST_PREFLIGHTS",
		"Longhorn.S3Override":                             "LONGHORN_S3_OVERRIDE",
		"Longhorn.StorageOverProvisioningPercentage":      "LONGHORN_STORAGE_OVER_PROVISIONING_PERCENTAGE",
		"Longhorn.UiBindPort":                             "LONGHORN_UI_BIND_PORT",
		"Longhorn.UiReplicaCount":                         "LONGHORN_UI_REPLICA_COUNT",
		"Longhorn.Version":                                "LONGHORN_VERSION",
		"MetricsServer.S3Override":                        "METRICS_SERVER_S3_OVERRIDE",
		"MetricsServer.Version":                           "METRICS_SERVER_VERSION",
		"Minio.Namespace":                                 "MINIO_NAMESPACE",
		"Minio.ClaimSize":                                 "MINIO_CLAIM_SIZE",
		"Minio.S3Override":                                "MINIO_S3_OVERRIDE",
		"Minio.HostPath":                                  "MINIO_HOSTPATH",
		"Minio.Version":                                   "MINIO_VERSION",
		"OpenEBS.CstorStorageClassName":                   "OPENEBS_CSTOR_STORAGE_CLASS",
		"OpenEBS.IsCstorEnabled":                          "OPENEBS_CSTOR",
		"OpenEBS.IsLocalPVEnabled":                        "OPENEBS_LOCALPV",
		"OpenEBS.LocalPVStorageClassName":                 "OPENEBS_LOCALPV_STORAGE_CLASS",
		"OpenEBS.Namespace":                               "OPENEBS_NAMESPACE",
		"OpenEBS.S3Override":                              "OPENEBS_S3_OVERRIDE",
		"OpenEBS.Version":                                 "OPENEBS_VERSION",
		"Prometheus.ServiceType":                          "PROMETHEUS_SERVICE_TYPE",
		"Prometheus.S3Override":                           "PROMETHEUS_S3_OVERRIDE",
		"Prometheus.Version":                              "PROMETHEUS_VERSION",
		"Registry.PublishPort":                            "REGISTRY_PUBLISH_PORT",
		"Registry.S3Override":                             "REGISTRY_S3_OVERRIDE",
		"Registry.Version":                                "REGISTRY_VERSION",
		"Rook.BlockDeviceFilter":                          "ROOK_BLOCK_DEVICE_FILTER",
		"Rook.BypassUpgradeWarning":                       "ROOK_BYPASS_UPGRADE_WARNING",
		"Rook.CephReplicaCount":                           "CEPH_POOL_REPLICAS",
		"Rook.HostpathRequiresPrivileged":                 "ROOK_HOSTPATH_REQUIRES_PRIVILEGED",
		"Rook.IsBlockStorageEnabled":                      "ROOK_BLOCK_STORAGE_ENABLED",
		"Rook.IsSharedFilesystemDisabled":                 "ROOK_SHARED_FILESYSTEM_DISABLED",
		"Rook.Nodes":                                      "ROOK_NODES",
		"Rook.MinimumNodeCount":                           "ROOK_MINIMUM_NODE_COUNT",
		"Rook.S3Override":                                 "ROOK_S3_OVERRIDE",
		"Rook.StorageClassName":                           "STORAGE_CLASS",
		"Rook.MinimumNodeCount":                           "ROOK_MINIMUM_NODE_COUNT",
		"Rook.Version":                                    "ROOK_VERSION",
		"SelinuxConfig.DisableSelinux":                    "DISABLE_SELINUX",
		"SelinuxConfig.PreserveConfig":                    "PRESERVE_SELINUX_CONFIG",
		"Sonobuoy.S3Override":                             "SONOBUOY_S3_OVERRIDE",
		"Sonobuoy.Version":                                "SONOBUOY_VERSION",
		"UFWConfig.BypassUFWWarning":                      "BYPASS_UFW_WARNING",
		"UFWConfig.DisableUFW":                            "DISABLE_UFW",
		"UFWConfig.HardFailOnUFW":                         "HARD_FAIL_ON_UFW",
		"Velero.DisableCLI":                               "VELERO_DISABLE_CLI",
		"Velero.DisableRestic":                            "VELERO_DISABLE_RESTIC",
		"Velero.LocalBucket":                              "VELERO_LOCAL_BUCKET",
		"Velero.Namespace":                                "VELERO_LOCAL_BUCKET",
		"Velero.ResticRequiresPrivileged":                 "VELERO_RESTIC_REQUIRES_PRIVILEGED",
		"Velero.ResticTimeout":                            "VELERO_RESTIC_TIMEOUT",
		"Velero.ServerFlags":                              "VELERO_SERVER_FLAGS",
		"Velero.S3Override":                               "VELERO_S3_OVERRIDE",
		"Velero.Version":                                  "VELERO_VERSION",
		"Weave.IsEncryptionDisabled":                      "ENCRYPT_NETWORK",
		"Weave.PodCIDR":                                   "POD_CIDR",
		"Weave.PodCidrRange":                              "POD_CIDR_RANGE",
		"Weave.S3Override":                                "WEAVE_S3_OVERRIDE",
		"Weave.Version":                                   "WEAVE_VERSION",
		"Weave.NoMasqLocal":                               "NO_MASQ_LOCAL",
		"Antrea.IsEncryptionDisabled":                     "ANTREA_DISABLE_ENCRYPTION",
		"Antrea.PodCIDR":                                  "ANTREA_POD_CIDR",
		"Antrea.PodCidrRange":                             "ANTREA_POD_CIDR_RANGE",
		"Antrea.S3Override":                               "ANTREA_S3_OVERRIDE",
		"Antrea.Version":                                  "ANTREA_VERSION",
		"Flannel.PodCIDR":                                 "FLANNEL_POD_CIDR",
		"Flannel.PodCIDRRange":                            "FLANNEL_POD_CIDR_RANGE",
		"Flannel.S3Override":                              "FLANNEL_S3_OVERRIDE",
		"Flannel.Version":                                 "FLANNEL_VERSION",
		"Goldpinger.Version":                              "GOLDPINGER_VERSION",
		"Goldpinger.S3Override":                           "GOLDPINGER_S3_OVERRIDE",
		"AWS.Version":                                     "AWS_VERSION",
		"AWS.S3Override":                                  "AWS_S3_OVERRIDE",
		"AWS.ExcludeStorageClass":                         "AWS_EXCLUDE_STORAGE_CLASS",
	}

	finalDictionary := make(map[string]string)

	for yamlKey, val := range kurlValues {
		if checkIfSkippedVariable(yamlKey) {
			//certain variables from the crd are handled by go binaries and not parsed into bash variables
			continue
		}

		bashKey, ok := bashLookup[yamlKey]
		if !ok {
			return nil, fmt.Errorf("%v not found in lookup table, it has not been added to the lookup table or is not in this version of kurlkinds", yamlKey)
		}

		var bashVal string

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
				// preserve inner double quotes
				ts := strings.ReplaceAll(t, `"`, `\"`)
				bashVal = "\"" + ts + "\""
			}
		case bool:
			if t {
				bashVal = "1"
			} else {
				bashVal = ""
			}
		case *bool:
			if t != nil {
				bashVal = strconv.FormatBool(*t)
			}
		case []string:
			if len(t) > 0 {
				bashVal = strings.Join(t, ",")
			}
		}

		switch {
		case yamlKey == "Kubernetes.LoadBalancerAddress" && bashVal != "":
			finalDictionary["HA_CLUSTER"] = "1"
		case yamlKey == "Kurl.Airgap" && bashVal != "":
			finalDictionary["OFFLINE_DOCKER_INSTALL"] = "1"
		case yamlKey == "Weave.PodCidrRange" || yamlKey == "Kubernetes.ServiceCidrRange" || yamlKey == "Antrea.PodCidrRange" || yamlKey == "Flannel.PodCIDRRange" && bashVal != "":
			bashVal = strings.Replace(bashVal, "/", "", -1)
		case yamlKey == "Docker.HardFailOnLoopback" && bashVal == "" && !fieldsSet[yamlKey]:
			bashVal = "1"
		case yamlKey == "Weave.NoMasqLocal":
			if bashVal == "true" || bashVal == "" {
				bashVal = "1"
			}
			if bashVal == "false" {
				bashVal = "0"
			}
		}

		finalDictionary[bashKey] = bashVal
	}

	// If preserve and disable flags are set for selinux and firewalld preserve take precedence
	val := finalDictionary["PRESERVE_FIREWALLD_CONFIG"]

	if val == "1" {
		finalDictionary["DISABLE_FIREWALLD"] = ""
	}

	val = finalDictionary["PRESERVE_SELINUX_CONFIG"]

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

	insertDefaults(installerConfig)

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

func insertDefaults(installerConfig *kurlv1beta1.Installer) {
	if installerConfig.Spec.Kubernetes == nil {
		installerConfig.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
	}

	if installerConfig.Spec.Kubernetes.ClusterName == "" {
		installerConfig.Spec.Kubernetes.ClusterName = "kubernetes"
	}
}

func main() {
	utilruntime.Must(kurlscheme.AddToScheme(scheme.Scheme))

	version := flag.Bool("v", false, "Print version info")
	installerYAMLPath := flag.String("i", "", "installer YAML for kURL script")
	bashVariablesPath := flag.String("b", "", "the path for the out file of bash variables")

	flag.Parse()

	if *version {
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
