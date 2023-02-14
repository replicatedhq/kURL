package host

import (
	"fmt"
	"os"
	"strings"
)

// GetHostname returns the node hostname using kubernetes as lib to ensure that will obtain the same value
// This code is the same used kubernetes project: (We copied to avoid to add a dependency only because of this snipt)
// https://github.com/kubernetes/kubernetes/blob/6b34fafdaf5998039c7e01fa33920a641b216d3e/staging/src/k8s.io/component-helpers/node/util/hostname.go#L25-L46
func GetHostname() (string, error) {
	nodeName, err := os.Hostname()
	if err != nil {
		return "", fmt.Errorf("couldn't determine hostname: %w", err)
	}
	hostName := nodeName

	// Trim whitespaces first to avoid getting an empty hostname
	// For linux, the hostname is read from file /proc/sys/kernel/hostname directly
	hostName = strings.TrimSpace(hostName)
	if len(hostName) == 0 {
		return "", fmt.Errorf("empty hostname is invalid")
	}

	return strings.ToLower(hostName), nil
}
