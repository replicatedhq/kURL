package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"io/ioutil"
	"log"
	"os"

	"github.com/pkg/errors"
	kurlscheme "github.com/replicatedhq/kurl/kurlkinds/client/kurlclientset/scheme"
	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
	kurlversion "github.com/replicatedhq/kurl/pkg/version"
	"k8s.io/client-go/kubernetes/scheme"
)

func main() {
	kurlscheme.AddToScheme(scheme.Scheme)

	version := flag.Bool("v", false, "Print version info")
	merge := flag.Bool("m", false, "Merge docker config in the YAML file with the one on the system. Must be accompanied by -cp [config_path] -yp [yaml_path]")
	replace := flag.Bool("r", false, "Replace docker config in the YAML file with the one on the system. Must be accompanied by -cp [config_path] -yp [yaml_path]")
	configPath := flag.String("cp", "", "docker config file name")
	yamlPath := flag.String("yp", "", "override yaml file name")

	flag.Parse()

	if *version == true {
		kurlversion.Print()
	} else if *merge == true && *configPath != "" && *yamlPath != "" {
		if err := mergeConfig(*configPath, *yamlPath); err != nil {
			log.Fatal(err)
		}
	} else if *replace == true && *configPath != "" && *yamlPath != "" {
		if err := replaceConfig(*configPath, *yamlPath); err != nil {
			log.Fatal(err)
		}
	} else {
		flag.PrintDefaults()
		os.Exit(-1)
	}
}

func mergeConfig(configPath string, yamlPath string) error {
	oldConfig, err := ioutil.ReadFile(configPath)
	if err != nil && !os.IsNotExist(err) {
		return errors.Wrapf(err, "failed to read file %s", configPath)
	}

	newConfig, err := getDockerConfigFromYaml(yamlPath)
	if err != nil {
		return errors.Wrap(err, "failed to load docker config")
	}

	mergedConfig, err := mergeConfigData(oldConfig, newConfig)
	if err != nil {
		return errors.Wrap(err, "failed to merge configs")
	}

	if len(mergedConfig) == 0 {
		// don't mess with file's existence and permissions if both configs are empty
		return nil
	}

	// TODO: preserve permissions
	if err := ioutil.WriteFile(configPath, mergedConfig, 0644); err != nil {
		return errors.Wrapf(err, "failed to write file %s", configPath)
	}

	return nil
}

func mergeConfigData(oldConfigData []byte, newConfigData []byte) ([]byte, error) {
	oldConfigData = bytes.TrimSpace(oldConfigData)
	newConfigData = bytes.TrimSpace(newConfigData)

	if len(oldConfigData) == 0 && len(newConfigData) == 0 {
		return nil, nil
	}

	if len(oldConfigData) == 0 {
		return newConfigData, nil
	}

	if len(newConfigData) == 0 {
		return oldConfigData, nil
	}

	oldConfig := make(map[string]interface{})
	if err := json.Unmarshal(oldConfigData, &oldConfig); err != nil {
		return nil, errors.Wrap(err, "failed to parse existing config")
	}

	newConfig := make(map[string]interface{})
	if err := json.Unmarshal(newConfigData, &newConfig); err != nil {
		return nil, errors.Wrap(err, "failed to parse new config")
	}

	mergedConfig := mergeMaps(oldConfig, newConfig)

	mergedConfigData, err := json.MarshalIndent(mergedConfig, "", "  ")
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal merged config")
	}

	return mergedConfigData, nil
}

func mergeMaps(oldConfig map[string]interface{}, newConfig map[string]interface{}) map[string]interface{} {
	mergedConfig := make(map[string]interface{})

	allKeys := mergeKeys(oldConfig, newConfig)
	for _, key := range allKeys {
		oldVal, oldOk := oldConfig[key]
		newVal, newOk := newConfig[key]

		if oldOk && !newOk {
			mergedConfig[key] = oldVal
			continue
		}

		if !oldOk && newOk {
			mergedConfig[key] = newVal
			continue
		}

		oldValMap, isOldMap := oldVal.(map[string]interface{})
		if !isOldMap {
			mergedConfig[key] = newVal
			continue
		}

		newValMap, isNewMap := newVal.(map[string]interface{})
		if !isNewMap {
			mergedConfig[key] = newVal
			continue
		}

		mergedConfig[key] = mergeMaps(oldValMap, newValMap)
	}
	return mergedConfig
}

func mergeKeys(config1 map[string]interface{}, config2 map[string]interface{}) []string {
	mergedMap := make(map[string]struct{})
	for key := range config1 {
		mergedMap[key] = struct{}{}
	}
	for key := range config2 {
		mergedMap[key] = struct{}{}
	}

	allKeys := make([]string, 0)
	for key := range mergedMap {
		allKeys = append(allKeys, key)
	}

	return allKeys
}

func replaceConfig(configPath string, yamlPath string) error {
	newConfig, err := getDockerConfigFromYaml(yamlPath)
	if err != nil {
		return errors.Wrap(err, "failed to load docker config")
	}

	// TODO: preserve permissions
	if err := ioutil.WriteFile(configPath, newConfig, 0644); err != nil {
		return errors.Wrapf(err, "failed to write file %s", configPath)
	}

	return nil
}

func getDockerConfigFromYaml(yamlPath string) ([]byte, error) {
	yamlData, err := ioutil.ReadFile(yamlPath)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to load file %s", yamlPath)
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

	return []byte(installer.Spec.Docker.DaemonConfig), nil
}
