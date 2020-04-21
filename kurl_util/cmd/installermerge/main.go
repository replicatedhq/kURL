package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"

	"github.com/pkg/errors"
	kurlscheme "github.com/replicatedhq/kurl/kurlkinds/client/kurlclientset/scheme"
	kurlversion "github.com/replicatedhq/kurl/pkg/version"
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
			mergedConfig[key] = "merged"
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

func mergeConfig(mergedYAMLPath string, baseYamlPath string, overlayYamlPath string) error {
	baseConfig, err := getInstallerConfigFromYaml(baseYamlPath)
	if err != nil {
		return errors.Wrap(err, "failed to load base config")
	}

	overlayConfig, err := getInstallerConfigFromYaml(overlayYamlPath)
	if err != nil {
		return errors.Wrap(err, "failed to load overlay config")
	}

	mergedConfig, err := mergeYamlConfigData(baseConfig, overlayConfig)
	if err != nil {
		return errors.Wrap(err, "failed to merge configs")
	}

	if len(mergedConfig) == 0 {
		// don't mess with file's existence and permissions if both configs are empty
		return nil
	}

	if err := writeSpec(mergedYAMLPath, mergedConfig); err != nil {
		return errors.Wrapf(err, "failed to write file %s", mergedYAMLPath)
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

	version := flag.Bool("v", false, "Print version info")
	mergedYAMLPath := flag.String("m", "", "combined file name")
	baseYAMLPath := flag.String("b", "", "base YAML file name")
	overlayYAMLPath := flag.String("o", "", "overlay YAML file name")

	flag.Parse()

	if *version == true {
		kurlversion.Print()
		return
	}

	if *mergedYAMLPath == "" || *baseYAMLPath == "" || *overlayYAMLPath == "" {
		flag.PrintDefaults()
		os.Exit(-1)
	}

	if err := mergeConfig(*mergedYAMLPath, *baseYAMLPath, *overlayYAMLPath); err != nil {
		log.Fatal(err)
	}
}
