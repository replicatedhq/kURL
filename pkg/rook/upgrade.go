package rook

import (
	"context"
	"fmt"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

const (
	waitForRookOrCephVersionLoopSleep = 10 * time.Second
)

// WaitForRookOrCephVersion waits for all deployments to report that they are using the specified rook (or ceph) version (depending on provided label key)
// and replicas are updated and ready.
// see https://rook.io/docs/rook/v1.10/Upgrade/rook-upgrade/#4-wait-for-the-upgrade-to-complete
func WaitForRookOrCephVersion(ctx context.Context, client kubernetes.Interface, desiredVersion string, labelKey string, name string) error {
	desiredVersion = normalizeRookVersion(desiredVersion)
	out(fmt.Sprintf("Waiting for all Rook-Ceph deployments to be using %s %s", name, desiredVersion))
	errCount := 0
	for {
		deployments, err := client.AppsV1().Deployments("rook-ceph").List(ctx, metav1.ListOptions{LabelSelector: "rook_cluster=rook-ceph"})
		if err != nil {
			errCount++
			if errCount >= 5 {
				return fmt.Errorf("failed to list Rook deployments 5x in a row: %w", err)
			}
		} else {
			errCount = 0 // only fail for _consecutive_ errors
		}

		ok, messages := hasRookOrCephVersion(deployments, desiredVersion, labelKey)
		if ok {
			return nil
		}

		updatedLine(strings.Join(messages, " and "))

		select {
		case <-time.After(waitForRookOrCephVersionLoopSleep):
		case <-ctx.Done():
			return fmt.Errorf("timed out waiting for %s %s to roll out", name, desiredVersion)
		}
	}
}

func hasRookOrCephVersion(deployments *appsv1.DeploymentList, desiredVersion string, labelKey string) (bool, []string) {
	oldVersions := map[string][]string{}
	notreadyNames := []string{}
	// compare labels with desired version
	for _, dep := range deployments.Items {
		rookVer := normalizeRookVersion(dep.Labels[labelKey])
		if rookVer != desiredVersion {
			if strings.Contains(rookVer, "0.0.0") || len(rookVer) == 0 {
				// Ignore this scenario because Rook versions < 1.4.8 has a bug where the version is not set.
				continue
			}
			_, ok := oldVersions[rookVer]
			if !ok {
				oldVersions[rookVer] = []string{dep.Name}
			} else {
				oldVersions[rookVer] = append(oldVersions[rookVer], dep.Name)
			}
		}
		if dep.Status.Replicas != dep.Status.UpdatedReplicas || dep.Status.Replicas != dep.Status.ReadyReplicas {
			notreadyNames = append(notreadyNames, dep.Name)
		}
	}

	if len(oldVersions) == 0 && len(notreadyNames) == 0 {
		return true, nil
	}

	// print a line describing what old versions are present or what deployments are yet updated and ready
	messages := []string{}
	for ver, names := range oldVersions {
		messages = append(messages, fmt.Sprintf("deployments %s still running %s", strings.Join(names, ", "), ver))
	}
	if len(notreadyNames) > 0 {
		messages = append(messages, fmt.Sprintf("deployments %s not ready", strings.Join(notreadyNames, ", ")))
	}

	return false, messages
}

// normalizeRookVersion trims the "v" prefix from a rook version.
func normalizeRookVersion(v string) string {
	return strings.TrimPrefix(v, "v")
}
