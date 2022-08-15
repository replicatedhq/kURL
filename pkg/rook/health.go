package rook

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/replicatedhq/kurl/pkg/rook/cephtypes"
	"k8s.io/client-go/kubernetes"
)

// RookHealth checks if rook-ceph is in a healthy state (by kURL standards), and returns healthy, a message describing why things are unhealthy, and errors encountered determining the status.
func RookHealth(ctx context.Context, client kubernetes.Interface) (bool, string, error) {
	cephStatus, err := currentStatus(ctx, client)
	if err != nil {
		return false, "", err
	}

	health, msg := isStatusHealthy(cephStatus)
	return health, msg, nil
}

func isStatusHealthy(status cephtypes.CephStatus) (bool, string) {
	statusMessage := []string{}

	if status.Health.Status != "HEALTH_OK" {
		statusMessage = append(statusMessage, fmt.Sprintf("health is %s not HEALTH_OK", status.Health.Status))
	}

	if status.Pgmap.RecoveringBytesPerSec != 0 {
		statusMessage = append(statusMessage, fmt.Sprintf("%d bytes are being recovered per second, 0 desired", status.Pgmap.RecoveringBytesPerSec))
	}

	if status.Pgmap.InactivePgsRatio != 0 || status.Pgmap.DegradedRatio != 0 || status.Pgmap.MisplacedRatio != 0 {
		statusMessage = append(statusMessage, fmt.Sprintf("%f%% of PGs are inactive, %f%% are degraded, and %f%% are misplaced, 0 required for all", status.Pgmap.InactivePgsRatio*100, status.Pgmap.DegradedRatio*100, status.Pgmap.MisplacedRatio*100))
	}

	if len(statusMessage) != 0 {
		return false, strings.Join(statusMessage, " and ")
	}

	return true, ""
}

func currentStatus(ctx context.Context, client kubernetes.Interface) (cephtypes.CephStatus, error) {
	err := startToolbox(ctx, client)
	if err != nil {
		return cephtypes.CephStatus{}, fmt.Errorf("failed to start toolbox, required for rook health checks: %w", err)
	}

	healthJSON, err := runToolboxCommand(ctx, client, []string{"ceph", "status", "--format", "json-pretty"})
	if err != nil {
		return cephtypes.CephStatus{}, fmt.Errorf("failed to run 'ceph status --format json-pretty': %w", err)
	}

	cephStatus := cephtypes.CephStatus{}
	err = json.Unmarshal([]byte(healthJSON), &cephStatus)
	if err != nil {
		return cephtypes.CephStatus{}, fmt.Errorf("failed to decode 'ceph status --format json-pretty': %w", err)
	}
	return cephStatus, nil
}

func progressMessage(status cephtypes.CephStatus) string {
	if status.Pgmap.InactivePgsRatio != 0 || status.Pgmap.DegradedRatio != 0 || status.Pgmap.MisplacedRatio != 0 {
		return fmt.Sprintf("%f%% of PGs are inactive, %f%% are degraded, and %f%% are misplaced; recovering at %d B/sec", status.Pgmap.InactivePgsRatio*100, status.Pgmap.DegradedRatio*100, status.Pgmap.MisplacedRatio*100, status.Pgmap.RecoveringBytesPerSec)
	}

	return ""
}

// this waits for ceph to report that there are more OSDs known than up, and thus that ceph actually recognizes that an OSD has been scaled down
func waitForOSDDown(ctx context.Context, client kubernetes.Interface) error {
	errCount := 0
	for {
		cephStatus, err := currentStatus(ctx, client)
		if err != nil {
			errCount++
			if errCount >= 5 {
				return fmt.Errorf("failed to wait for Rook health 5x in a row: %w", err)
			}
		} else {
			errCount = 0 // only fail for _consecutive_ errors

			if cephStatus.Osdmap.Osdmap.NumOsds > cephStatus.Osdmap.Osdmap.NumUpOsds {
				return nil
			}
		}

		select {
		case <-time.After(loopSleep):
			spinner()
		case <-ctx.Done():
			return fmt.Errorf("timed out waiting rook to mark osd as out")
		}
	}
}

func waitForHealth(ctx context.Context, client kubernetes.Interface, osdToRemove int64) error {
	errCount := 0
	safeErrCount := 0
	var isHealthy bool
	var healthMessage string
	for {
		cephStatus, err := currentStatus(ctx, client)
		if err != nil {
			errCount++
			if errCount >= 5 {
				return fmt.Errorf("failed to wait for Rook health 5x in a row: %w", err)
			}
		} else {
			errCount = 0 // only fail for _consecutive_ errors

			isHealthy, healthMessage = isStatusHealthy(cephStatus)
			if isHealthy {
				// if the cluster is healthy, check if the osd is safe to remove
				// if it is not safe to remove, keep waiting
				isOkToRemove, offendingPgs, err := safeToRemoveOSD(ctx, client, osdToRemove)
				if err != nil {
					safeErrCount++
					if safeErrCount >= 5 {
						return fmt.Errorf("failed to check if it was safe to remove osd %d 5 times: %w", osdToRemove, err)
					}
				} else {
					safeErrCount = 0 // only fail for _consecutive_ errors
					if isOkToRemove {
						return nil
					}
					spinLine(fmt.Sprintf("Waiting for %d PGs to be moved off of osd.%d before removing it", offendingPgs, osdToRemove))
				}
			} else {
				// print a status message
				spinLine(progressMessage(cephStatus))
			}
		}

		select {
		case <-time.After(loopSleep):
		case <-ctx.Done():
			return fmt.Errorf("timed out waiting rook to become healthy again, currently %q", healthMessage)
		}
	}
}

// safeToRemoveOSD determines if the OSD is safe to remove
func safeToRemoveOSD(ctx context.Context, client kubernetes.Interface, osd int64) (bool, int, error) {
	safetodestroy, err := runToolboxCommand(ctx, client, []string{"ceph", "osd", "safe-to-destroy", fmt.Sprintf("osd.%d", osd)})
	if err != nil {
		return false, -1, fmt.Errorf("unable to check if osd %d is safe to destroy: %w", osd, err)
	}

	isSafe, remainingPGs := parseSafeToRemoveOSD(safetodestroy)
	return isSafe, remainingPGs, nil
}

var safeToRemoveOSDRegex = regexp.MustCompile(`OSD\(s\) \d+ are safe to destroy without reducing data durability\.`)
var pendingPgsOnOSDRegex = regexp.MustCompile(`Error EBUSY: OSD\(s\) \d+ have (\d+) pgs currently mapped to them\.`)

// parse the output of `ceph osd safe-to-destroy osd.<num>` and return if the OSD is safe to destroy and how many PGs remain
func parseSafeToRemoveOSD(output string) (bool, int) {
	if safeToRemoveOSDRegex.MatchString(output) {
		return true, 0
	}

	pendingPgsMatch := pendingPgsOnOSDRegex.FindStringSubmatch(output)
	if pendingPgsMatch != nil && len(pendingPgsMatch) >= 2 {
		pgnum, err := strconv.ParseInt(pendingPgsMatch[1], 10, 32)
		if err == nil {
			return false, int(pgnum)
		}
	}

	return false, -1
}
