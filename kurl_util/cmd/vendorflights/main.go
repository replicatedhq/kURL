package main

import (
	"bytes"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"

	"github.com/replicatedhq/kurl/kurlkinds/client/kurlclientset/scheme"
	"github.com/replicatedhq/kurl/pkg/installer"
	serializer "k8s.io/apimachinery/pkg/runtime/serializer/json"
)

// takes the path to installer spec yaml
func extractPreflightSpec(inputPath string, outputPath string) error {

	data, err := ioutil.ReadFile(inputPath)
	if err != nil {
		return err
	}
	installerSpec, err := installer.DecodeSpec(data)
	if err != nil {
		return err
	}
	if installerSpec.Spec.Kurl == nil {
		return nil
	}
	var b bytes.Buffer
	if installerSpec.Spec.Kurl.HostPreflights != nil {
		hostPreflights := installerSpec.Spec.Kurl.HostPreflights

		if hostPreflights.APIVersion != "troubleshoot.sh/v1beta2" {
			return fmt.Errorf("invalid HostPreflight APIVersion - troubleshoot.sh/v1beta2 required")
		}

		s := serializer.NewYAMLSerializer(serializer.DefaultMetaFactory, scheme.Scheme, scheme.Scheme)

		if err := s.Encode(hostPreflights, &b); err != nil {
			return fmt.Errorf("failed to reserialize yaml %w", err)
		}

		if err := writeSpec(outputPath, b.Bytes()); err != nil {
			return fmt.Errorf("failed to write file %s %w", outputPath, err)
		}

	}

	return nil
}

func writeSpec(filename string, spec []byte) error {
	err := os.MkdirAll(filepath.Dir(filename), 0755)
	if err != nil {
		return fmt.Errorf("failed to create script dir %w", err)
	}

	f, err := os.OpenFile(filename, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return fmt.Errorf("failed to create script file %w", err)
	}
	defer f.Close()

	_, err = f.Write(spec)
	if err != nil {
		return fmt.Errorf("failed to create script file %w", err)
	}

	return nil
}

// -i INPATH: Input path to kurl installer spec file
// -o OUTPATH: Output path for file to write the troubleshoot spec to
func main() {

	inputPath := flag.String("i", "", "Input path for kurl installer yaml")
	outputPath := flag.String("o", "", "Output path for troubleshoot preflight spec yaml")
	flag.Parse()

	err := extractPreflightSpec(*inputPath, *outputPath)
	if err != nil {
		log.Fatalf("Failed to extract preflight spec: %q", err)
	}

}
