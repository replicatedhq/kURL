package rook

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/replicatedhq/kurl/pkg/rook/cephtypes"
	"k8s.io/client-go/kubernetes"
)

// RookHealth checks if rook-ceph is in a healthy state (by kURL standards), and returns healthy, a
// message describing why things are unhealthy, and errors encountered determining the status.
// Individual checks can be ignored by passing in a list of Ceph health check unique identifiers
// (https://docs.ceph.com/en/quincy/rados/operations/health-checks/) to ignore.
func RookHealth(ctx context.Context, client kubernetes.Interface, ignoreChecks []string) (bool, string, error) {
	cephStatus, err := currentStatus(ctx, client)
	if err != nil {
		return false, "", err
	}

	health, msg := isStatusHealthy(cephStatus, ignoreChecks)
	return health, msg, nil
}

// WaitForRookHealth waits for rook-ceph to report that it is healthy 5 times in a row. Individual
// checks can be ignored by passing in a list of Ceph health check unique identifiers
// (https://docs.ceph.com/en/quincy/rados/operations/health-checks/) to ignore.
func WaitForRookHealth(ctx context.Context, client kubernetes.Interface, ignoreChecks []string) error {
	out("Waiting for Rook-Ceph to be healthy")
	errCount, successCount := 0, 0
	var isHealthy bool
	var healthMessage string
	for {
		cephStatus, err := currentStatus(ctx, client)
		if err != nil {
			errCount++
			if errCount >= 5 {
				return fmt.Errorf("failed to wait for rook health 5x in a row: %w", err)
			}
		} else {
			errCount = 0 // only fail for _consecutive_ errors

			isHealthy, healthMessage = isStatusHealthy(cephStatus, ignoreChecks)
			if isHealthy {
				successCount++
				if successCount >= 5 {
					return nil
				}
			} else {
				successCount = 0
				// print a status message
				spinLine(progressMessage(cephStatus))
			}

		}

		select {
		case <-time.After(loopSleep):
		case <-ctx.Done():
			return fmt.Errorf("timed out waiting rook to become healthy, currently %q", healthMessage)
		}
	}
}

func isStatusHealthy(status cephtypes.CephStatus, ignoreChecks []string) (bool, string) {
	statusMessage := []string{}

	if status.Health.Status != "HEALTH_OK" {
		// this is not an error we need to stop upgrades for (this will show up after upgrading from 1.0 until autoscaling pgs is enabled)
		// TODO: factor this out since it is specific to the upgrade scenario and not general
		delete(status.Health.Checks, "TOO_MANY_PGS")

		// this is not an error we need to stop upgrades for (it will always be present on single node installs)
		delete(status.Health.Checks, "POOL_NO_REDUNDANCY")

		// recent crash errors aren't likely to go away while we're waiting
		delete(status.Health.Checks, "RECENT_CRASH")

		// ignore "pool(s) have non-power-of-two pg_num", as Ceph will continue to work and will not prevent upgrades
		delete(status.Health.Checks, "POOL_PG_NUM_NOT_POWER_OF_TWO")

		// ignore "mon is allowing insecure global_id reclaim", as Ceph will continue to work and will not prevent upgrades
		// note that it is required to upgrade from 1.0.4-14.2.21 to 1.4.9
		delete(status.Health.Checks, "AUTH_INSECURE_GLOBAL_ID_RECLAIM_ALLOWED")

		// By default, the following warning will be raised when more than 70% of the mon
		// space be in usage. (df -h /var/lib/ceph/mon) This is not an error we need to stop upgrades for
		// https://docs.ceph.com/en/quincy/rados/operations/health-checks/#mon-disk-low
		delete(status.Health.Checks, "MON_DISK_LOW")

		for _, check := range ignoreChecks {
			delete(status.Health.Checks, check)
		}

		if len(status.Health.Checks) != 0 {
			unhealthReasons := []string{}
			for _, v := range status.Health.Checks {
				unhealthReasons = append(unhealthReasons, v.Summary.Message)
			}
			sort.Strings(unhealthReasons)

			statusMessage = append(statusMessage, fmt.Sprintf("health is %s because %q", status.Health.Status, strings.Join(unhealthReasons, " and ")))
		}
	}

	if status.Pgmap.RecoveringBytesPerSec != 0 {
		statusMessage = append(statusMessage, fmt.Sprintf("%d bytes are being recovered per second, 0 desired", status.Pgmap.RecoveringBytesPerSec))
	}

	if status.Pgmap.InactivePgsRatio != 0 || status.Pgmap.DegradedRatio != 0 || status.Pgmap.MisplacedRatio != 0 {
		statusMessage = append(statusMessage, fmt.Sprintf("%f%% of PGs are inactive, %f%% are degraded, and %f%% are misplaced, 0 required for all", status.Pgmap.InactivePgsRatio*100, status.Pgmap.DegradedRatio*100, status.Pgmap.MisplacedRatio*100))
	}

	progressEventsMessage := progressEventsString(status)
	if progressEventsMessage != "" {
		statusMessage = append(statusMessage, progressEventsMessage)
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

	healthJSON, _, err := runToolboxCommand(ctx, client, []string{"ceph", "status", "--format", "json-pretty"})
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

func progressEventsString(status cephtypes.CephStatus) string {
	if len(status.ProgressEvents) != 0 {
		// only show the first progress event, as there may be quite a few
		eventKeys := []string{}
		for key := range status.ProgressEvents {
			eventKeys = append(eventKeys, key)
		}
		sort.Strings(eventKeys)

		var firstEvent struct {
			Message  string  `json:"message"`
			Progress float64 `json:"progress"`
		}
		for _, event := range eventKeys {
			// we do not consider a global recovery event to be enough to make ceph be 'unhealthy'
			if !strings.Contains(status.ProgressEvents[event].Message, "Global Recovery Event") {
				firstEvent = status.ProgressEvents[event]
				break
			}
		}

		if firstEvent.Message == "" {
			return ""
		}

		firstEvent.Message = strings.ReplaceAll(firstEvent.Message, "\n", "")

		return fmt.Sprintf("%d tasks in progress, first task %q is %f%% complete", len(status.ProgressEvents), firstEvent.Message, firstEvent.Progress*100)
	}

	return ""
}

func progressMessage(status cephtypes.CephStatus) string {
	progressEventsMessage := progressEventsString(status)
	if progressEventsMessage != "" {
		return progressEventsMessage
	}

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

func waitForOkToRemoveOSD(ctx context.Context, client kubernetes.Interface, osdToRemove int64) error {
	errCount := 0
	safeErrCount := 0
	okCount := 0
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

			isHealthy, healthMessage = isStatusHealthy(cephStatus, nil)
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
						if okCount >= 2 { // require that the cluster be healthy and the OSD be safe to remove 3x in a row before removal
							return nil
						}
						okCount++
					} else {
						okCount = 0
					}
					updatedLine(fmt.Sprintf("Waiting for %d PGs to be moved off of osd.%d before removing it", offendingPgs, osdToRemove))
				}
			} else {
				okCount = 0
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
	_, safetodestroy, err := runToolboxCommand(ctx, client, []string{"ceph", "osd", "safe-to-destroy", fmt.Sprintf("osd.%d", osd)})
	if err != nil {
		if safetodestroy != "" {
			// check if we know about this message and it is safe to ignore
			isSafe, remainingPGs := parseSafeToRemoveOSD(safetodestroy)
			if remainingPGs != -1 {
				return isSafe, remainingPGs, nil
			}
		}
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
	if len(pendingPgsMatch) >= 2 {
		pgnum, err := strconv.ParseInt(pendingPgsMatch[1], 10, 32)
		if err == nil {
			return false, int(pgnum)
		}
	}

	out(fmt.Sprintf("Unable to parse %q", output))
	return false, -1
}
