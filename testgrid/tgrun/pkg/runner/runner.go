package runner

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"

	"github.com/pkg/errors"
	tghandlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/types"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/vmi"
)

func Run(singleTest types.SingleRun, uploadProxyURL, tempDir string) error {
	err := execute(singleTest, uploadProxyURL, tempDir)

	if err != nil {
		fmt.Println("execute failed")
		fmt.Println("  ID:", singleTest.ID)
		fmt.Println("  REF:", singleTest.KurlRef)
		fmt.Println("  ERROR:", err)
		if reportError := reportFailed(singleTest, err); reportError != nil {
			return errors.Wrap(err, "failed to report test failed")
		}
	}

	return nil
}

func reportStarted(singleTest types.SingleRun) error {
	startInstanceRequest := tghandlers.StartInstanceRequest{
		OSName:    singleTest.OperatingSystemName,
		OSVersion: singleTest.OperatingSystemVersion,
		OSImage:   singleTest.OperatingSystemImage,

		Memory: singleTest.Memory,
		CPU:    singleTest.CPU,

		KurlSpec: singleTest.KurlYAML,
		KurlRef:  singleTest.KurlRef,
		KurlURL:  singleTest.KurlURL,
	}

	b, err := json.Marshal(startInstanceRequest)
	if err != nil {
		return errors.Wrap(err, "failed to marshal request")
	}

	req, err := http.NewRequest("POST", fmt.Sprintf("%s/v1/instance/%s/start", singleTest.TestGridAPIEndpoint, singleTest.ID), bytes.NewReader(b))
	if err != nil {
		return errors.Wrap(err, "failed to create request")
	}
	req.Header.Set("Content-Type", "application/json")
	_, err = http.DefaultClient.Do(req)
	if err != nil {
		return errors.Wrap(err, "failed to execute request")
	}

	return nil
}

func reportFailed(singleTest types.SingleRun, testErr error) error {
	return nil
}

// pathify OS image by removing non-alphanumeric characters
func urlToPath(url string) string {
	return regexp.MustCompile(`[^a-zA-Z0-9]`).ReplaceAllString(url, "")
}

func execute(singleTest types.SingleRun, uploadProxyURL, tempDir string) error {
	osImagePath := urlToPath(singleTest.OperatingSystemImage)

	_, err := os.Stat(filepath.Join(tempDir, osImagePath))
	if err != nil {
		fmt.Printf("  [downloading from %s]\n", singleTest.OperatingSystemImage)

		// Download the img
		resp, err := http.Get(singleTest.OperatingSystemImage)
		if err != nil {
			return errors.Wrap(err, "failed to get")
		}
		defer resp.Body.Close()

		// Create the file
		out, err := os.Create(filepath.Join(tempDir, osImagePath))
		if err != nil {
			return errors.Wrap(err, "failed to create image file")
		}
		defer out.Close()

		// Write the body to file
		_, err = io.Copy(out, resp.Body)
		if err != nil {
			return errors.Wrap(err, "failed to save vm image")
		}

		fmt.Printf("   [image downloaded]\n")
	} else {
		fmt.Printf("  [using existng image on disk at %s for %s]\n", filepath.Join(tempDir, osImagePath), singleTest.OperatingSystemImage)
	}
	// create initial primary node
	if err = vmi.Create(singleTest, vmi.InitPrimaryNode, vmi.InitPrimaryNode, tempDir, osImagePath, uploadProxyURL); err != nil {
		return errors.Wrap(err, "failed to create vm for init primary node")
	}
	// create primary nodes where we exclude the initial primary node so I will start with 1
	// todo to use goroutine to create the nodes
	for i := 1; i < singleTest.NumPrimaryNodes; i++ {
		primaryNodeName := fmt.Sprintf("%s-%d", vmi.PrimaryNode, i)
		fmt.Println("  [creating primary node", primaryNodeName, "]")
		if err = vmi.Create(singleTest, primaryNodeName, vmi.PrimaryNode, tempDir, osImagePath, uploadProxyURL); err != nil {
			return errors.Wrap(err, "failed to create vm for primary node "+strconv.Itoa(i))
		}
	}
	// create secondary nodes
	for i := 0; i < singleTest.NumSecondaryNodes; i++ {
		secondaryNodeName := fmt.Sprintf("%s-%d", vmi.SecondaryNode, i)
		fmt.Println("  [creating secondary node", secondaryNodeName, "]")
		if err = vmi.Create(singleTest, secondaryNodeName, vmi.SecondaryNode, tempDir, osImagePath, uploadProxyURL); err != nil {
			return errors.Wrap(err, "failed to create vm for secondary node "+strconv.Itoa(i))
		}
	}

	// mark the instance started
	// we do this after the data volume is uploaded
	if err := reportStarted(singleTest); err != nil {
		return errors.Wrap(err, "failed to report test started")
	}

	return nil
}
