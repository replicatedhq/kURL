package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"log"

	"github.com/replicatedhq/kurl/pkg/installer"
)

// takes the path to installer spec yaml
func extractPreflightSpec(inputPath string, outputPath string) error {

	fmt.Println(inputPath)
	data, err := ioutil.ReadFile(inputPath)
	if err != nil {
		return err
	}
	installerSpec, err := installer.DecodeSpec(data)
	if err != nil {
		return err
	}

	fmt.Println(installerSpec)

	return nil
}

// arg1: path to kurl installer spec .yaml
// arg2: output file to write the troubleshoot spec to
func main() {

	fmt.Println("##################")
	inputPath := flag.String("i", "", "Input path for kurl installer yaml")
	outputPath := flag.String("o", "", "Output path for troubleshoot preflight spec yaml")

	err := extractPreflightSpec(*inputPath, *outputPath)
	if err != nil {
		log.Fatalf("Failed to extract preflight spec: %q", err)
	}

}
