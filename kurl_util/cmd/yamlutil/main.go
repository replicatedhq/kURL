package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strings"

	"gopkg.in/yaml.v2"
)

func readFile(path string) []byte {
	file, err := os.Open(path)

	if err != nil {
		log.Fatal(err)
	}

	defer file.Close()

	configuration, err := ioutil.ReadAll(file)

	if err != nil {
		log.Fatal(err)
	}

	return configuration
}

func removeField(filePath, yamlField string) {
	var buffer []byte

	configuration := readFile(filePath)

	resources := bytes.Split(configuration, []byte("---"))

	for _, config := range resources {

		var parsed interface{}

		err := yaml.Unmarshal(config, &parsed)

		if err != nil {
			log.Fatalf("error: %v", err)
		}

		if parsed == nil {
			continue
		}

		delete(parsed.(map[interface{}]interface{}), yamlField)

		b, err := yaml.Marshal(&parsed)

		if err != nil {
			log.Fatal(err)
		}

		buffer = append(buffer, b...)
		buffer = append(buffer, []byte("---\n")...)
	}

	err := ioutil.WriteFile(filePath, buffer, 0644)

	if err != nil {
		log.Fatalf("error: %v", err)
	}
}

func retrieveField(filePath, yamlPath string) {
	configuration := readFile(filePath)

	var parsed interface{}

	err := yaml.Unmarshal(configuration, &parsed)

	if err != nil {
		log.Fatalf("error: %v", err)
	}

	fields := strings.Split(yamlPath, "_")

	if len(fields) != 2 {
		log.Fatalf("Yaml path must be of 2 length")
	}

	concrete := parsed.(map[interface{}]interface{})
	data := concrete[fields[0]]

	concrete = data.(map[interface{}]interface{})
	data = concrete[fields[1]]

	err = ioutil.WriteFile(filePath, []byte(data.(string)), 0644)

	if err != nil {
		log.Fatalf("error: %v", err)
	}
}

func jsonField(filePath, jsonPath string) {
	configuration := readFile(filePath)

	var parsed interface{}

	err := yaml.Unmarshal(configuration, &parsed)

	if err != nil {
		log.Fatalf("error: %v", err)
	}

	fields := strings.Split(jsonPath, ".")

	// get the specified field
	for _, field := range fields {
		concrete := parsed.(map[interface{}]interface{})
		parsed = concrete[field]
	}

	if parsedInterface, ok := parsed.(map[interface{}]interface{}); ok {
		parsed = convertToStringMaps(parsedInterface)
	}

	// convert the remaining object to json
	jsonObj, err := json.Marshal(parsed)
	if err != nil {
		log.Fatalf("error: %v, parsed %+v", err, parsed)
	}
	fmt.Printf("%s\n", jsonObj)
}

func convertToStringMaps(startMap map[interface{}]interface{}) map[string]interface{} {
	converted := map[string]interface{}{}
	for key, val := range startMap {
		if valMap, ok := val.(map[interface{}]interface{}); ok { // this does not handle the case of map[interface]interface within arrays, but that is not needed yet
			val = convertToStringMaps(valMap)
		}
		if keyString, ok := key.(string); ok {
			converted[keyString] = val
		} else {
			strKey := fmt.Sprintf("%v", key)
			converted[strKey] = val
		}
	}
	return converted
}

func main() {

	remove := flag.Bool("r", false, "Removes a yaml field and its children. Must be accompanied by -fp [file_path] -yf [yaml_field]")
	parse := flag.Bool("p", false, "Parses a yaml tree given a path. Must be accompanied by -fp [file_path] -yp [yaml_path]. yaml_path is delineated by '_'")
	json := flag.Bool("j", false, "Parses a yaml tree given a path. Must be accompanied by -fp [file_path] -jf [json_field]. json_field is delineated by '.'")
	filePath := flag.String("fp", "", "filepath")
	yamlPath := flag.String("yp", "", "filepath")
	yamlField := flag.String("yf", "", "filepath")
	jsonPath := flag.String("jf", "", "path to a field within a yaml object")

	flag.Parse()

	if *remove == true && *filePath != "" && *yamlField != "" {
		removeField(*filePath, *yamlField)
	} else if *parse == true && *filePath != "" && *yamlPath != "" {
		retrieveField(*filePath, *yamlPath)
	} else if *json == true && *filePath != "" && *jsonPath != "" {
		jsonField(*filePath, *jsonPath)
	} else {
		log.Fatalf("incorrect binary usage")
	}
}
