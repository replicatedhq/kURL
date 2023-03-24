package main

import (
	"bytes"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/pkg/errors"
	kurlscheme "github.com/replicatedhq/kurlkinds/client/kurlclientset/scheme"
	kurlv1beta1 "github.com/replicatedhq/kurlkinds/pkg/apis/cluster/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	serializer "k8s.io/apimachinery/pkg/runtime/serializer/json"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/kubernetes/scheme"
)

func getInstallerConfigFromYaml(yamlPath string) (*kurlv1beta1.Installer, error) {
	yamlData, err := os.ReadFile(yamlPath)
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
		return nil, errors.Errorf("installer yaml contained unexpected gvk: %s/%s/%s", gvk.Group, gvk.Version, gvk.Kind)
	}

	installer := obj.(*kurlv1beta1.Installer)

	return installer, nil
}

func checkIfFlagHasValue(length int, flag string) bool {
	shouldHaveLengthTwo := []string{
		"additional-no-proxy-addresses",
		"cert-key",
		"docker-registry-ip",
		"kubeadm-token",
		"kubeadm-token-ca-hash",
		"kubernetes-master-address",
		"kubernetes-version",
		"load-balancer-address",
		"public-address",
		"private-address",
	}

	for _, variable := range shouldHaveLengthTwo {
		if variable == flag {
			return length == 2
		}
	}
	return true
}

func parseBashFlags(installer *kurlv1beta1.Installer, bashFlags string) error {
	s := strings.Split(strings.TrimSpace(bashFlags), " ")

	for _, flag := range s {
		split := strings.SplitN(flag, "=", 2)

		if !checkIfFlagHasValue(len(split), split[0]) {
			return fmt.Errorf("flag %s does not have a value", split[0])
		}

		switch split[0] {

		case "additional-no-proxy-addresses":
			addresses := strings.Split(split[1], ",")
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.AdditionalNoProxyAddresses = append(installer.Spec.Kurl.AdditionalNoProxyAddresses, addresses...)
		case "airgap":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.Airgap = true
		case "aws-exclude-storage-class":
			if installer.Spec.AWS == nil {
				installer.Spec.AWS = &kurlv1beta1.AWS{}
			}
			installer.Spec.AWS.ExcludeStorageClass = true
		case "cert-key":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.CertKey = split[1]
		case "control-plane":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.ControlPlane = true
		case "docker-registry-ip":
			if installer.Spec.Docker == nil {
				installer.Spec.Docker = &kurlv1beta1.Docker{}
			}
			installer.Spec.Docker.DockerRegistryIP = split[1]
		case "ha":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.HACluster = true
		case "container-log-max-size":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.ContainerLogMaxSize = split[1]
		case "container-log-max-files":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			m, err := strconv.Atoi(split[1])
			if err != nil {
				return errors.Wrap(err, "invalid container-log-max-files value. must be an integer.")
			}
			installer.Spec.Kubernetes.ContainerLogMaxFiles = m
		case "kubeadm-token":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.KubeadmToken = split[1]
		case "kubeadm-token-ca-hash":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.KubeadmTokenCAHash = split[1]
		case "load-balancer-address":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.LoadBalancerAddress = split[1]
		case "ekco-enable-internal-load-balancer":
			if installer.Spec.Ekco != nil {
				installer.Spec.Ekco.EnableInternalLoadBalancer = true
			}
		case "kubernetes-load-balancer-use-first-primary":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.LoadBalancerUseFirstPrimary = true
		case "kubernetes-master-address":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.MasterAddress = split[1]
			if split[1] == "localhost:6444" && installer.Spec.Ekco != nil {
				installer.Spec.Ekco.EnableInternalLoadBalancer = true
			}
		case "kubernetes-cis-compliance":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.CisCompliance = true
		case "kubernetes-cluster-name":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.ClusterName = split[1]
		case "kubernetes-version":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.Version = strings.TrimLeft(split[1], "v")
		case "kurl-install-directory":
			continue
		case "installer-spec-file":
			continue
		case "kurl-registry-ip":
			continue
		case "labels":
			continue
		case "ignore-remote-load-images-prompt":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.IgnoreRemoteLoadImagesPrompt = true
		case "ignore-remote-upgrade-prompt":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.IgnoreRemoteUpgradePrompt = true
		case "host-preflight-ignore", "preflight-ignore":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.HostPreflightIgnore = true
		// Legacy flag; this flag was a no-op as the installer always ignored host preflights
		case "preflight-ignore-warnings":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
		case "host-preflight-enforce-warnings":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.HostPreflightEnforceWarnings = true
		case "dismiss-host-packages-preflight": // possibly add this to the spec
			continue
		case "preserve-docker-config":
			if installer.Spec.Docker == nil {
				installer.Spec.Docker = &kurlv1beta1.Docker{}
			}
			installer.Spec.Docker.PreserveConfig = true
		case "preserve-firewalld-config":
			if installer.Spec.FirewalldConfig == nil {
				installer.Spec.FirewalldConfig = &kurlv1beta1.FirewalldConfig{}
			}
			installer.Spec.FirewalldConfig.PreserveConfig = true
		case "preserve-iptables-config":
			if installer.Spec.IptablesConfig == nil {
				installer.Spec.IptablesConfig = &kurlv1beta1.IptablesConfig{}
			}
			installer.Spec.IptablesConfig.PreserveConfig = true
		case "preserve-selinux-config":
			if installer.Spec.SelinuxConfig == nil {
				installer.Spec.SelinuxConfig = &kurlv1beta1.SelinuxConfig{}
			}
			installer.Spec.SelinuxConfig.PreserveConfig = true
		case "public-address":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.PublicAddress = split[1]
		case "private-address":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.PrivateAddress = split[1]
		case "skip-system-package-install":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.SkipSystemPackageInstall = true
		case "exclude-builtin-host-preflights", "exclude-builtin-preflights":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.ExcludeBuiltinHostPreflights = true
		case "app-version-label":
			if installer.Spec.Kotsadm == nil {
				installer.Spec.Kotsadm = &kurlv1beta1.Kotsadm{}
			}
			installer.Spec.Kotsadm.ApplicationVersionLabel = split[1]
		case "yes":
			continue
		case "auto-upgrades-enabled": // no longer supported
			continue
		case "primary-host":
			continue
		case "secondary-host":
			continue
		case "force-reapply-addons": // no longer supported
			continue
		case "ipv6":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.IPv6 = true
		case "velero-restic-timeout":
			if installer.Spec.Velero == nil {
				installer.Spec.Velero = &kurlv1beta1.Velero{}
			}
			installer.Spec.Velero.ResticTimeout = split[1]
		case "velero-server-flags":
			// velero server flags may contain equals signs, so we need to rejoin the rest of the string if it was split
			flags := strings.Split(strings.Join(split[1:], "="), ",")
			if installer.Spec.Velero == nil {
				installer.Spec.Velero = &kurlv1beta1.Velero{}
			}
			installer.Spec.Velero.ServerFlags = append(installer.Spec.Velero.ServerFlags, flags...)
		default:
			return fmt.Errorf("string %s is not a bash flag", split[0])
		}
	}

	return nil
}

func mergeConfig(currentYAMLPath string, bashFlags string) error {
	currentConfig, err := getInstallerConfigFromYaml(currentYAMLPath)
	if err != nil {
		return errors.Wrap(err, "failed to load current config")
	}

	if err := parseBashFlags(currentConfig, bashFlags); err != nil {
		return errors.Wrapf(err, "failed to parse flag string %q", bashFlags)
	}

	// Hack to get around the serialization of this field to "null" in YAML, which is not a valid Object type
	// int the installer CRD when sending the installer spec back to k8s.
	// See https://github.com/kubernetes/kubernetes/issues/67610
	if currentConfig.Spec.Kurl != nil && currentConfig.Spec.Kurl.HostPreflights != nil {
		currentConfig.Spec.Kurl.HostPreflights.ObjectMeta.CreationTimestamp = metav1.Now()
	}

	s := serializer.NewYAMLSerializer(serializer.DefaultMetaFactory, scheme.Scheme, scheme.Scheme)

	var b bytes.Buffer
	if err := s.Encode(currentConfig, &b); err != nil {
		return errors.Wrap(err, "failed to reserialize yaml")
	}

	if err := writeSpec(currentYAMLPath, b.Bytes()); err != nil {
		return errors.Wrapf(err, "failed to write file %s", currentYAMLPath)
	}

	return nil
}

func writeSpec(filename string, spec []byte) error {
	err := os.MkdirAll(filepath.Dir(filename), 0755)
	if err != nil {
		return errors.Wrap(err, "failed to create script dir")
	}

	f, err := os.OpenFile(filename, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return errors.Wrap(err, "failed to create script file")
	}
	defer f.Close()

	_, err = f.Write(spec)
	if err != nil {
		return errors.Wrap(err, "failed to write script file")
	}

	return nil
}

func main() {
	utilruntime.Must(kurlscheme.AddToScheme(scheme.Scheme))

	currentYAMLPath := flag.String("c", "", "current yaml file")
	bashFlags := flag.String("f", "", "bash flag overwrites")

	flag.Parse()

	if *currentYAMLPath == "" || *bashFlags == "" {
		flag.PrintDefaults()
		os.Exit(-1)
	}

	if err := mergeConfig(*currentYAMLPath, *bashFlags); err != nil {
		log.Fatal(err)
	}
}
