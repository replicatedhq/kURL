package host

import (
	"fmt"
	"os"
	"strings"
)

// GetHostname returns the node hostname using kubernetes as lib to ensure that will obtain the same value
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
