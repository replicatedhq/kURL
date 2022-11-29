package rook

import (
	"context"
	"fmt"
	"strings"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// WaitForRookOrCephVersion waits for all deployments to report that they are using the specified rook (or ceph) version (depending on provided label key)
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

			oldVersions := map[string][]string{}
			// compare labels with desired version
			for _, dep := range deployments.Items {
				rookVer := normalizeRookVersion(dep.Labels[labelKey])
				if rookVer != desiredVersion {
					_, ok := oldVersions[rookVer]
					if !ok {
						oldVersions[rookVer] = []string{dep.Name}
					} else {
						oldVersions[rookVer] = append(oldVersions[rookVer], dep.Name)
					}
				}
			}

			if len(oldVersions) == 0 {
				return nil
			}

			// print a line describing what old versions are present
			versionMessages := []string{}
			for ver, names := range oldVersions {
				versionMessages = append(versionMessages, fmt.Sprintf("deployments %s still running %s", strings.Join(names, ", "), ver))
			}

			updatedLine(strings.Join(versionMessages, " and "))
		}

		select {
		case <-time.After(loopSleep):
		case <-ctx.Done():
			return fmt.Errorf("timed out waiting for %s %s to roll out", name, desiredVersion)
		}
	}
}

// normalizeRookVersion trims the "v" prefix from a rook version.
func normalizeRookVersion(v string) string {
	return strings.TrimPrefix(v, "v")
}
