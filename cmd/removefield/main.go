package main

import (
	"log"
	"os"
	"io/ioutil"
	"bytes"

	"gopkg.in/yaml.v2"
)

func readFile (path string) []byte {
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

func removeField(path, field string) {
	var buffer []byte

	configuration := readFile(path)

	resources := bytes.Split(configuration, []byte("---"))

	for _, config :=  range resources {

		var parsed interface{}

		err := yaml.Unmarshal(config, &parsed)

		if err != nil {
			log.Fatalf("error: %v", err)
		}

		delete(parsed.(map[interface {}]interface{}), field)

		b, err := yaml.Marshal(&parsed)

		if err != nil {
			log.Fatal(err)
		}

		buffer = append(buffer, b...)
		buffer = append(buffer, []byte("---\n")...)
	}

	err := ioutil.WriteFile(path, buffer, 0644)

	if err != nil {
		log.Fatalf("error: %v", err)
	}
}

func main() {
	if len(os.Args) != 3 {
		log.Fatalf("Usage: ./remove_field filename field")
	}

	filePath := os.Args[1]

	field := os.Args[2]

	removeField(filePath, field)
}
