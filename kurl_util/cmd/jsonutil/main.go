package main

import (
	"encoding/json"
	"flag"
	"io/ioutil"
	"log"
	"os"
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

func prettifyJSON(readFile func(string) []byte, filePath string) {
	config := readFile(filePath)

	var parsed interface{}
	if err := json.Unmarshal(config, &parsed); err != nil {
		log.Fatalf("error: %v", err)
	}
	if parsed == nil {
		return
	}

	b, err := json.MarshalIndent(parsed, "", "  ")
	if err != nil {
		log.Fatal(err)
	}

	if err := ioutil.WriteFile(filePath, b, 0644); err != nil {
		log.Fatalf("error: %v", err)
	}
}

func main() {
	prettify := flag.Bool("p", false, "Prettifies the content of a json file. Must be accompanied by -fp [file_path]")
	filePath := flag.String("fp", "", "filepath")

	flag.Parse()

	if *prettify == true && *filePath != "" {
		prettifyJSON(readFile, *filePath)
	} else {
		log.Fatalf("incorrect binary usage")
	}
}
