package main

import (
	"bytes"
	"flag"
	"io/ioutil"
	"log"
	"os"
	"strings"
	"reflect"
	"fmt"
	"strconv"
	"sort"

	"github.com/pkg/errors"
	kurlscheme "github.com/replicatedhq/kurl/kurlkinds/client/kurlclientset/scheme"
	kurlversion "github.com/replicatedhq/kurl/pkg/version"
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	"k8s.io/client-go/kubernetes/scheme"
)

func getInstallerConfigFromYaml(yamlPath string) (*kurlv1beta1.Installer, error) {
	yamlData, err := ioutil.ReadFile(yamlPath)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to load file %s", yamlPath)
	}

	yamlData = bytes.TrimSpace(yamlData)
	if len(yamlData) == 0 {
		return nil, nil
	}

	decode := scheme.Codecs.UniversalDeserializer().Decode

	obj, gvk, err := decode(yamlData, nil, nil)
	if err != nil {
		return nil, errors.Wrap(err, "failed to decode installer yaml")
	}

	if gvk.Group != "cluster.kurl.sh" || gvk.Version != "v1beta1" || gvk.Kind != "Installer" {
		return nil, errors.Errorf("installer yaml contained unepxected gvk: %s/%s/%s", gvk.Group, gvk.Version, gvk.Kind)
	}
	installer := obj.(*kurlv1beta1.Installer)

	return installer, nil
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

func convertToBash(kurlValues map[string]interface{}) (map[string]string, error) {
	bashLookup := map[string]string{
		"Contour.Version" : "CONTOUR_VERSION",
		"Docker.BypassStorageDriverWarning": "BYPASS_STORAGEDRIVER_WARNINGS",
		"Docker.DockerRegistryIp": "DOCKER_REGISTRY_IP",
		"Docker.HardFailOnLoopback": "HARD_FAIL_ON_LOOPBACK",
		"Docker.NoCEOnEE": "NO_CE_ON_EE",
		"Docker.NoDocker": "SKIP_DOCKER_INSTALL",
		"Docker.Version": "DOCKER_VERSION",
		"Ekco.MinReadyMasterNodeCount": "EKCO_MIN_READY_MASTER_NODE_COUNT",
		"Ekco.MinReadyWorkerNodeCount": "EKCO_MIN_READY_WORKER_NODE_COUNT",
		"Ekco.NodeUnreachableToleration": "EKCO_NODE_UNREACHABLE_TOLERATION_DURATION",
		"Ekco.RookShouldUseAllNodes": "EKCO_ROOK_SHOULD_USE_ALL_NODES",
		"Ekco.ShouldDisableRebootServices": "EKCO_SHOULD_DISABLE_REBOOT_SERVICE",
		"Ekco.Version:" : "EKCO_VERSION",
		"FirewalldConfig.Preserve": "PRESERVE_FIREWALLD_CONFIG",
		"Fluentd.FullEFKStack": "FLUENTD_FULL_EFK_STACK",
		"Fluentd.Version": "FLUENTD_VERSION",
		"IptablesConfig.Preserve": "PRESERVE_IPTABLES_CONFIG",
		"Kotsadm.ApplicationNamespace": "KOTSADM_APPLICATION_NAMESPACES",
		"Kotsadm.ApplicationSlug": "KOTSADM_APPLICATION_SLUG",
		"Kotsadm.Hostname": "KOTSADM_HOSTNAME",
		"Kotsadm.UiBindPort": "KOTSADM_UI_BIND_PORT",
		"Kotsadm.Version": "KOTSADM_VERSION",
		"Kubernetes.BootstrapToken": "BOOTSTRAP_TOKEN",
		"Kubernetes.BootstrapTokenTTL": "BOOTSTRAP_TOKEN_TTL",
		"Kubernetes.CertKey": "CERT_KEY",
		"Kubernetes.ControlPlane": "MASTER",
		"Kubernetes.HACluster": "HA_CLUSTER",
		"Kubernetes.KubeadmTokenCAHash": "KUBEADM_TOKEN",
		//TODO deal with lba
		"Kubernetes.LoadBalancerAddress": "LOAD_BALANCER_ADDRESS",
		"Kubernetes.MasterAddress": "KUBERNETES_MASTER_ADDR",
		"Kubernetes.ServiceCIDR": "SERVICE_CIDR",
		//TODO handle this sed
		"Kubernetes.ServiceCidrRange": "SERVICE_CIDR_RANGE",
		"Kubernetes.Version": "KUBERNETES_VERSION",
		//TODO deal multiple airgap
		"Kurl.Airgap": "AIRGAP",
		"Kurl.BypassFirewalldWarning": "BYPASS_FIREWALLD_WARNING",
		"Kurl.HTTPProxy": "PROXY_ADDRESS",
		"Kurl.HardFailOnFirewalld": "HARD_FAIL_ON_FIREWALLD",
		"Kurl.HostnameCheck": "HOSTNAME_CHECK",
		"Kurl.NoProxy": "NO_PROXY",
		"Kurl.PrivateAddress": "PRIVATE_ADDRESS",
		"Kurl.PublicAddress": "PUBLIC_ADDRESS",
		"Kurl.Task": "TASK",
		"Minio.Namespace": "MINIO_NAMESPACE",
		"Minio.Version": "MINIO_VERSION",
		"OpenEBS.CstorStorageClassName": "OPENEBS_CSTOR_STORAGE_CLASS",
		"OpenEBS.IsCstorEnabled": "OPENEBS_CSTOR",
		"OpenEBS.IsLocalPVEnabled": "OPENEBS_LOCALPV",
		"OpenEBS.LocalPVStorageClassName": "OPENEBS_LOCALPV_STORAGE_CLASS",
		"OpenEBS.Namespace": "OPENEBS_VERSION",
		"OpenEBS.Version": "OPENEBS_VERSION",
		"Prometheus.Version": "PROMETHEUS_VERSION",
		"Registry.Version": "REGISTRY_VERSION",
		"Rook.BlockDeviceFilter": "ROOK_BLOCK_DEVICE_FILTER",
		"Rook.CephReplicaCount": "CEPH_POOL_REPLICAS",
		"Rook.IsBlockStorageEnabled": "ROOK_BLOCK_STORAGE_ENABLED",
		"Rook.StorageClassName": "STORAGE_CLASS",
		"Rook.Version": "ROOK_VERSION",
		"SelinuxConfig.Preserve": "PRESERVE_SELINUX_CONFIG",
		"Velero.DisableCLI": "VELERO_DISABLE_CLI",
		"Velero.DisableRestic": "VELERO_DISABLE_RESTIC",
		"Velero.LocalBucket": "VELERO_LOCAL_BUCKET",
		"Velero.Namespace": "VELERO_LOCAL_BUCKET",
		"Velero.Version": "VELERO_VERSION",
		"Weave.PodCIDR": "POD_CIDR",
		//TODO handle this sed
		"Weave.PodCidrRange": "POD_CIDR_RANGE",
		"Weave.Version": "WEAVE_VERSION",
	}

	finalDictionary := make(map[string]string)

	var bashVal string

	for yamlKey, val := range kurlValues {


		bashKey, ok := bashLookup[yamlKey]
		if ok == false{
			// return nil, fmt.Errorf("Install CRD does not have the kind %v, check spelling in lookup or update dependency", yamlKey)
			continue
		}

		switch t := interface{}(val).(type) {
		case int:
			if t == 0 {
				bashVal = ""
			} else {
				bashVal = strconv.Itoa(t)
			}
		case string:
			if t == ""{
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
		}

		finalDictionary[bashKey] = bashVal
	}

 	//TODO account for aigrap getting multiple keys

	return finalDictionary
}

func writeDictionaryToFile(bashDictionary map[string]string, bashPath string) error {
	var variables []string

	for k, v := range bashDictionary {
		variables = append(variables, k + "=" + v)
	}

	sort.Strings(variables)

    f, err := os.Create(bashPath)
	if err != nil {
        return errors.Wrap("failed to write bash variables to file")
    }
    defer f.Close()

    for _, value := range variables {
       fmt.Fprintln(f, value)  // print values to f, one per line
    }

	return nil
}

func addBashVariablesFromYaml(yamlPath, bashPath string) error {
	installerConfig, err := getInstallerConfigFromYaml(yamlPath)
	if err != nil {
		return errors.Wrap(err, "failed to load installer yaml")
	}

	yamlDictionary := createMap(installerConfig)

	bashDictionary, err := convertToBash(yamlDictionary)
	if err != nil {
		return err
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
	bashVariablesPath := flag.String("b", "", "the path for the temp file of bash variables")

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
