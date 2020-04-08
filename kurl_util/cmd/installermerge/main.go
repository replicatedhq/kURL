package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"

	"github.com/pkg/errors"
	kurlscheme "github.com/replicatedhq/kurl/kurlkinds/client/kurlclientset/scheme"
	"gopkg.in/yaml.v2"
	"k8s.io/client-go/kubernetes/scheme"
)

func getInstallerConfigFromYaml(yamlPath string) ([]byte, error) {
	yamlData, err := ioutil.ReadFile(yamlPath)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to load file %s", yamlPath)
	}

	yamlData = bytes.TrimSpace(yamlData)
	if len(yamlData) == 0 {
		return nil, nil
	}

	decode := scheme.Codecs.UniversalDeserializer().Decode
	_, gvk, err := decode(yamlData, nil, nil)
	if err != nil {
		return nil, errors.Wrap(err, "failed to decode installer yaml")
	}

	if gvk.Group != "cluster.kurl.sh" || gvk.Version != "v1beta1" || gvk.Kind != "Installer" {
		return nil, errors.Errorf("installer yaml contained unepxected gvk: %s/%s/%s", gvk.Group, gvk.Version, gvk.Kind)
	}

	return yamlData, nil
}

func convertToMapStringInterface(original map[interface{}]interface{}) map[string]interface{} {
	converted := make(map[string]interface{})

	for key, value := range original {
		switch key := key.(type) {
		case string:
			converted[key] = value
		}
	}

	return converted
}

func mergeYAMLMaps(oldConfig map[string]interface{}, newConfig map[string]interface{}) map[string]interface{} {
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

		if key == "daemonConfig" {
			mergedDockerConfig, _ := mergeDockerConfigData([]byte(oldVal.(string)), []byte(newVal.(string)))
			mergedConfig[key] = string(mergedDockerConfig)
			continue
		}

		oldValMap, isOldMap := oldVal.(map[interface{}]interface{})
		newValMap, isNewMap := newVal.(map[interface{}]interface{})
		if isNewMap && isOldMap {
			mergedConfig[key] = mergeYAMLMaps(convertToMapStringInterface(oldValMap), convertToMapStringInterface(newValMap))
			continue
		}

		oldValCommands, isOldCommands := oldVal.([][]string)
		newValCommands, isNewCommands := newVal.([][]string)
		if isOldCommands && isNewCommands {
			mergedConfig[key] = append(oldValCommands, newValCommands...)
			continue
		}

		if key == "name" {
			mergedConfig[key] = "Merged"
			continue
		}

		mergedConfig[key] = newVal

	}
	return mergedConfig
}

func mergeJSONMaps(oldConfig map[string]interface{}, newConfig map[string]interface{}) map[string]interface{} {
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

		mergedConfig[key] = mergeJSONMaps(oldValMap, newValMap)
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

func mergeDockerConfigData(oldconfigdata []byte, newconfigdata []byte) ([]byte, error) {
	oldconfigdata = bytes.TrimSpace(oldconfigdata)
	newconfigdata = bytes.TrimSpace(newconfigdata)

	if len(oldconfigdata) == 0 && len(newconfigdata) == 0 {
		return nil, nil
	}

	if len(oldconfigdata) == 0 {
		return newconfigdata, nil
	}

	if len(newconfigdata) == 0 {
		return oldconfigdata, nil
	}

	oldconfig := make(map[string]interface{})
	if err := json.Unmarshal(oldconfigdata, &oldconfig); err != nil {
		return nil, errors.Wrap(err, "failed to parse existing config")
	}

	newconfig := make(map[string]interface{})
	if err := json.Unmarshal(newconfigdata, &newconfig); err != nil {
		return nil, errors.Wrap(err, "failed to parse new config")
	}

	mergedconfig := mergeJSONMaps(oldconfig, newconfig)

	mergedconfigdata, err := json.MarshalIndent(mergedconfig, "", "  ")
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal merged config")
	}

	return mergedconfigdata, nil
}

func mergeYamlConfigData(oldconfigdata []byte, newconfigdata []byte) ([]byte, error) {
	oldconfigdata = bytes.TrimSpace(oldconfigdata)
	newconfigdata = bytes.TrimSpace(newconfigdata)

	if len(oldconfigdata) == 0 && len(newconfigdata) == 0 {
		return nil, nil
	}

	if len(oldconfigdata) == 0 {
		return newconfigdata, nil
	}

	if len(newconfigdata) == 0 {
		return oldconfigdata, nil
	}

	oldconfig := make(map[string]interface{})
	if err := yaml.Unmarshal(oldconfigdata, &oldconfig); err != nil {
		return nil, errors.Wrap(err, "failed to parse existing config")
	}

	newconfig := make(map[string]interface{})
	if err := yaml.Unmarshal(newconfigdata, &newconfig); err != nil {
		return nil, errors.Wrap(err, "failed to parse new config")
	}

	mergedconfig := mergeYAMLMaps(oldconfig, newconfig)

	mergedconfigdata, err := yaml.Marshal(mergedconfig)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal merged config")
	}

	return mergedconfigdata, nil
}

func main() {
	kurlscheme.AddToScheme(scheme.Scheme)

	oldInstaller, _ := getInstallerConfigFromYaml("old.yaml")
	newInstaller, _ := getInstallerConfigFromYaml("new.yaml")

	mergedConfigData, _ := mergeYamlConfigData(oldInstaller, newInstaller)
	fmt.Println(string(mergedConfigData))
}
