package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"strings"

	"github.com/pkg/errors"
	"gopkg.in/yaml.v2"
	yamlv3 "gopkg.in/yaml.v3"
)

func readFile(path string) []byte {
	file, err := os.Open(path)

	if err != nil {
		log.Fatal(err)
	}

	defer file.Close()

	configuration, err := io.ReadAll(file)

	if err != nil {
		log.Fatal(err)
	}

	return configuration
}

func marshalIndent(in interface{}, indent int) ([]byte, error) {
	var buf bytes.Buffer
	enc := yamlv3.NewEncoder(&buf)
	enc.SetIndent(indent)
	err := enc.Encode(in)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to encode with indent %d", indent)
	}
	return buf.Bytes(), nil
}

func addFieldToFile(readFile func(string) []byte, filePath, yamlPath, value string) {
	configuration := readFile(filePath)

	modified, err := addFieldToContent(configuration, yamlPath, value)
	if err != nil {
		log.Fatalf("error: %v", err)
	}

	err = os.WriteFile(filePath, []byte(modified), 0644)
	if err != nil {
		log.Fatalf("error: %v", err)
	}
}

func addFieldToContent(content []byte, yamlPath, value string) (string, error) {
	var parsedVal interface{}
	err := yaml.Unmarshal([]byte(value), &parsedVal)
	if err != nil {
		return "", errors.Wrap(err, "failed to unmarshal value")
	}

	var buffer []byte

	resources := bytes.Split(content, []byte("---"))

	for index, config := range resources {
		var parsedObj map[interface{}]interface{}

		err := yaml.Unmarshal(config, &parsedObj)
		if err != nil {
			return "", errors.Wrap(err, "failed to unmarshal content")
		}
		if parsedObj == nil {
			continue
		}

		isArray := strings.HasSuffix(yamlPath, "[]")
		yamlPath = strings.TrimSuffix(yamlPath, "[]")

		fields := strings.Split(yamlPath, "_")
		if len(fields) != 2 {
			return "", errors.New("yaml path must be of 2 length")
		}

		// if parent key doesn't exist, add it
		if _, ok := parsedObj[fields[0]]; !ok {
			parsedObj[fields[0]] = map[interface{}]interface{}{}
		}

		if isArray {
			arr := parsedObj[fields[0]].(map[interface{}]interface{})[fields[1]]
			if arr == nil {
				arr = []interface{}{}
			}
			parsedObj[fields[0]].(map[interface{}]interface{})[fields[1]] = append(arr.([]interface{}), parsedVal)
		} else {
			parsedObj[fields[0]].(map[interface{}]interface{})[fields[1]] = parsedVal
		}

		b, err := marshalIndent(parsedObj, 2)
		if err != nil {
			return "", errors.Wrap(err, "failed to marshal")
		}

		buffer = append(buffer, b...)

		// don't append "---" to the last document
		if index < len(resources)-1 {
			buffer = append(buffer, []byte("---\n")...)
		}
	}

	return string(buffer), nil
}

func removeFieldFromFile(readFile func(string) []byte, filePath, yamlPath string) {
	configuration := readFile(filePath)

	modified, err := removeFieldFromContent(configuration, yamlPath)
	if err != nil {
		log.Fatalf("error: %v", err)
	}

	err = os.WriteFile(filePath, []byte(modified), 0644)
	if err != nil {
		log.Fatalf("error: %v", err)
	}
}

func removeFieldFromContent(content []byte, yamlPath string) (string, error) {
	var buffer []byte

	resources := bytes.Split(content, []byte("---"))

	for index, config := range resources {
		var parsed map[interface{}]interface{}

		err := yaml.Unmarshal(config, &parsed)

		if err != nil {
			log.Fatalf("error: %v", err)
		}

		if parsed == nil {
			continue
		}

		parts := strings.Split(yamlPath, "_")
		if len(parts) == 1 {
			delete(parsed, yamlPath)
		} else if len(parts) == 2 {
			// check if parent key exists
			if _, ok := parsed[parts[0]]; ok {
				delete(parsed[parts[0]].(map[interface{}]interface{}), parts[1])
			}
		} else {
			return "", errors.New("yaml path parts length must be less than or equal to 2")
		}

		b, err := yaml.Marshal(&parsed)

		if err != nil {
			log.Fatal(err)
		}

		buffer = append(buffer, b...)

		// don't append "---" to the last document
		if index < len(resources)-1 {
			buffer = append(buffer, []byte("---\n")...)
		}
	}

	return string(buffer), nil
}

func retrieveField(readFile func(string) []byte, filePath, yamlPath string) {
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

	err = os.WriteFile(filePath, []byte(data.(string)), 0644)

	if err != nil {
		log.Fatalf("error: %v", err)
	}
}

func jsonField(readFile func(string) []byte, filePath, jsonPath string) (string, error) {
	configuration := readFile(filePath)

	var parsed interface{}

	err := yaml.Unmarshal(configuration, &parsed)

	if err != nil {
		return "", errors.Wrap(err, "unmarshal interface")
	}

	fields := strings.Split(jsonPath, ".")

	// get the specified field
	for _, field := range fields {
		concrete, ok := parsed.(map[interface{}]interface{})
		if !ok {
			return "", fmt.Errorf("error: struct is not a map[interface]interface when looking for field %s", field)
		}
		parsed, ok = concrete[field]
		if !ok {
			return "", fmt.Errorf("error: field %s is not present", field)
		}
	}

	if parsedInterface, ok := parsed.(map[interface{}]interface{}); ok {
		parsed = convertToStringMaps(parsedInterface)
	}

	// convert the remaining object to json
	jsonObj, err := json.Marshal(parsed)
	if err != nil {
		return "", errors.Wrapf(err, "parsed %+v", parsed)
	}
	return string(jsonObj), nil
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
	add := flag.Bool("a", false, "Adds a yaml field and its children. Must be accompanied by (-fp [file_path] or -yc [yaml_content]) -yp [yaml_path] -v [value]. yaml_path is delineated by '_'. if field is to be added to an array, yaml_path must end with '[]', for example: spec.collectors[]")
	remove := flag.Bool("r", false, "Removes a yaml field and its children. Must be accompanied by -fp [file_path] -yp [yaml_path]")
	parse := flag.Bool("p", false, "Parses a yaml tree given a path. Must be accompanied by -fp [file_path] -yp [yaml_path]. yaml_path is delineated by '_'")
	json := flag.Bool("j", false, "Parses a yaml tree given a path. Must be accompanied by -fp [file_path] -jf [json_field]. json_field is delineated by '.'")
	value := flag.String("v", "", "Value to assign to added yaml field. Must be accompanied by (-fp [file_path] or -yc [yaml_content]) -yp [yaml_path].")
	filePath := flag.String("fp", "", "filepath")
	yamlContent := flag.String("yc", "", "yamlcontent")
	yamlPath := flag.String("yp", "", "yamlpath")
	jsonPath := flag.String("jf", "", "path to a field within a yaml object")

	flag.Parse()

	if *add && *yamlPath != "" && *value != "" {
		if *filePath != "" {
			addFieldToFile(readFile, *filePath, *yamlPath, *value)
		} else if *yamlContent != "" {
			modified, err := addFieldToContent([]byte(*yamlContent), *yamlPath, *value)
			if err != nil {
				log.Fatal(err.Error())
			}
			fmt.Printf("%s\n", modified)
		}
	} else if *remove && *yamlPath != "" {
		if *filePath != "" {
			removeFieldFromFile(readFile, *filePath, *yamlPath)
		} else if *yamlContent != "" {
			modified, err := removeFieldFromContent([]byte(*yamlContent), *yamlPath)
			if err != nil {
				log.Fatal(err.Error())
			}
			fmt.Printf("%s\n", modified)
		}
	} else if *parse && *filePath != "" && *yamlPath != "" {
		retrieveField(readFile, *filePath, *yamlPath)
	} else if *json && *filePath != "" && *jsonPath != "" {
		jsonObj, err := jsonField(readFile, *filePath, *jsonPath)
		if err != nil {
			log.Fatal(err.Error())
		}
		fmt.Printf("%s\n", jsonObj)
	} else {
		log.Fatalf("incorrect binary usage")
	}
}
