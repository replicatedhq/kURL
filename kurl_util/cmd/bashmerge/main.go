package main

import (
	"bytes"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/pkg/errors"
	kurlscheme "github.com/replicatedhq/kurl/kurlkinds/client/kurlclientset/scheme"
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	serializer "k8s.io/apimachinery/pkg/runtime/serializer/json"
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
		split := strings.Split(flag, "=")

		if !checkIfFlagHasValue(len(split), split[0]) {
			return errors.New(fmt.Sprintf("flag %s does not have a value", split[0]))
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
		case "kubernetes-master-address":
			if installer.Spec.Kubernetes == nil {
				installer.Spec.Kubernetes = &kurlv1beta1.Kubernetes{}
			}
			installer.Spec.Kubernetes.MasterAddress = split[1]
			if split[1] == "localhost:6444" && installer.Spec.Ekco != nil {
				installer.Spec.Ekco.EnableInternalLoadBalancer = true
			}
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
		case "preflight-ignore":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.PreflightIgnore = true
		case "preflight-ignore-warnings":
			if installer.Spec.Kurl == nil {
				installer.Spec.Kurl = &kurlv1beta1.Kurl{}
			}
			installer.Spec.Kurl.PreflightIgnoreWarnings = true
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
		case "yes":
			continue
		case "auto-upgrades-enabled":
			continue
		case "primary-host":
			continue
		case "secondary-host":
			continue
		case "force-reapply-addons":
			continue
		default:
			return errors.New(fmt.Sprintf("string %s is not a bash flag", split[0]))
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
	kurlscheme.AddToScheme(scheme.Scheme)

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
