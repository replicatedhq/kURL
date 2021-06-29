package main

import (
	"bytes"
	"flag"
	"io/ioutil"
	"log"
	"os"
	"strings"

	"github.com/pkg/errors"
	kurlscheme "github.com/replicatedhq/kurl/kurlkinds/client/kurlclientset/scheme"
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	kurlversion "github.com/replicatedhq/kurl/pkg/version"
	"k8s.io/client-go/kubernetes/scheme"
)

func main() {
	kurlscheme.AddToScheme(scheme.Scheme)

	version := flag.Bool("v", false, "Print version info")
	configPath := flag.String("c", "", "docker config file name")
	yamlSpecPath := flag.String("s", "", "base yaml file name")

	flag.Parse()

	if *version == true {
		kurlversion.Print()
		return
	}

	if *configPath == "" || *yamlSpecPath == "" {
		flag.PrintDefaults()
		os.Exit(-1)
	}

	if err := saveConfig(*configPath, *yamlSpecPath); err != nil {
		log.Fatal(err)
	}
}

func saveConfig(configPath string, yamlSpecPath string) error {
	config, err := getDockerConfigFromYaml(yamlSpecPath)
	if err != nil {
		return errors.Wrap(err, "failed to load config")
	}

	if len(config) == 0 {
		// don't mess with file's existence and permissions if both configs are empty
		return nil
	}

	// TODO: preserve permissions
	if err := ioutil.WriteFile(configPath, config, 0644); err != nil {
		return errors.Wrapf(err, "failed to write file %s", configPath)
	}

	return nil
}

func getDockerConfigFromYaml(yamlPath string) ([]byte, error) {
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

	if installer.Spec.Docker == nil {
		return nil, nil
	}

	return []byte(strings.TrimSpace(installer.Spec.Docker.DaemonConfig)), nil
}
