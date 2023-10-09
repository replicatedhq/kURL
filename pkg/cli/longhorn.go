package cli

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/util/retry"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/config"

	lhv1b1 "github.com/longhorn/longhorn-manager/k8s/pkg/apis/longhorn/v1beta1"
	promv1 "github.com/prometheus-operator/prometheus-operator/pkg/apis/monitoring/v1"
	"github.com/spf13/cobra"
)

var scaleDownReplicasWaitTime = 5 * time.Minute

const (
	pvmigrateScaleDownAnnotation = "kurl.sh/pvcmigrate-scale"
	longhornNamespace            = "longhorn-system"
	overProvisioningSetting      = "storage-over-provisioning-percentage"
)

func NewLonghornCmd(cli CLI) *cobra.Command {
	return &cobra.Command{
		Use:   "longhorn",
		Short: "Perform operations on a longhorn installation within a kURL cluster",
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
	}
}

func NewLonghornRollbackMigrationReplicas(cli CLI) *cobra.Command {
	return &cobra.Command{
		Use:          "rollback-migration-replicas",
		Short:        "Rollback Longhorn Volumes, Deployments, and StetefulSet replicas to their original value.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			logger := cli.Logger()

			logger.Print("Rolling back Longhorn volume replicas to their original value.")
			cli, err := client.New(config.GetConfigOrDie(), client.Options{})
			if err != nil {
				return fmt.Errorf("error creating client: %s", err)
			}
			lhv1b1.AddToScheme(cli.Scheme())
			promv1.AddToScheme(cli.Scheme())

			var l1b1Volumes lhv1b1.VolumeList
			if err := cli.List(cmd.Context(), &l1b1Volumes, client.InNamespace(longhornNamespace)); err != nil {
				return fmt.Errorf("error listing longhorn volumes: %w", err)
			}

			for _, volume := range l1b1Volumes.Items {
				if _, ok := volume.Annotations[pvmigrateScaleDownAnnotation]; !ok {
					logger.Printf("Volume %s has not been scaled down, skipping.", volume.Name)
					continue
				}

				replicas, err := strconv.Atoi(volume.Annotations[pvmigrateScaleDownAnnotation])
				if err != nil {
					return fmt.Errorf("error parsing replica count for volume %s: %w", volume.Name, err)
				}

				logger.Printf("Rolling back volume %s to %d replicas.", volume.Name, replicas)

				// The Longhorn volume could become stale when we update it since volumes can be updated by the Longhorn manager operator
				// resulting in a conflict error.
				// To resolve this, retry the update operation until we no longer get a conflict error.
				retryUpdateErr := retry.RetryOnConflict(retry.DefaultRetry, func() error {
					nsn := types.NamespacedName{Namespace: longhornNamespace, Name: volume.Name}
					if err := cli.Get(cmd.Context(), nsn, &volume); err != nil {
						if errors.IsNotFound(err) {
							logger.Printf("Longhorn volume %s not found. Ignoring since object must have been deleted.", volume.Name)
							return nil
						}
						return fmt.Errorf("Failed to get Longhorn volume %s: %w", volume.Name, err)
					}

					// delete annotation
					delete(volume.Annotations, pvmigrateScaleDownAnnotation)

					// update replicas
					volume.Spec.NumberOfReplicas = replicas
					if err := cli.Update(cmd.Context(), &volume); err != nil {
						return fmt.Errorf("Failed to update Longhorn volume %s: %w", volume.Name, err)
					}
					return nil
				})

				if retryUpdateErr != nil {
					return fmt.Errorf("error rolling back volume %s replicas: %w", volume.Name, err)
				}
			}
			logger.Print("Longhorn volumes have been rolled back to their original replica count.")

			return nil
		},
	}
}

func NewLonghornPrepareForMigration(cli CLI) *cobra.Command {
	return &cobra.Command{
		Use:          "prepare-for-migration",
		Short:        "Prepares Longhorn for migration to a different storage provisioner.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			logger := cli.Logger()

			logger.Print("Preparing Longhorn for migration to a different storage provisioner.")
			cli, err := client.New(config.GetConfigOrDie(), client.Options{})
			if err != nil {
				return fmt.Errorf("error creating client: %s", err)
			}
			lhv1b1.AddToScheme(cli.Scheme())
			promv1.AddToScheme(cli.Scheme())

			var scaledDown bool
			var nodes corev1.NodeList
			if err := cli.List(cmd.Context(), &nodes); err != nil {
				return fmt.Errorf("error listing kubernetes nodes: %s", err)
			} else if len(nodes.Items) == 1 {
				logger.Print("Only one node found, scaling down the number of Longhorn volume replicas to 1.")
				if scaledDown, err = scaleDownReplicas(cmd.Context(), logger, cli); err != nil {
					return fmt.Errorf("error scaling down longhorn replicas: %s", err)
				}
			}

			unhealthy, err := unhealthyVolumes(cmd.Context(), logger, cli)
			if err != nil {
				return fmt.Errorf("error assessing unhealthy volumes: %s", err)
			}

			if len(unhealthy) > 0 {
				logger.Print("The following Longhorn volumes are unhealthy:")
				for _, vol := range unhealthy {
					logger.Printf(" - %s/%s", longhornNamespace, vol)
				}
				return fmt.Errorf("error preparing longhorn for migration: unhealthy volumes")
			}

			unhealthy, err = unhealthyNodes(cmd.Context(), logger, cli)
			if err != nil {
				return fmt.Errorf("error assessing unhealthy Longhorn nodes: %s", err)
			}

			if len(unhealthy) > 0 {
				logger.Print("The following Longhorn nodes are unhealthy:")
				for _, node := range unhealthy {
					logger.Printf(" - %s", node)
				}
				return fmt.Errorf("error preparing longhorn for migration: unhealthy nodes")
			}

			if scaledDown {
				logger.Printf("Storage volumes have been scaled down to 1 replica for the migration.")
				logger.Printf("If necessary, you can scale them back up to the original value with:")
				logger.Printf("")
				logger.Printf("$ kurl longhorn rollback-migration-replicas")
				logger.Printf("")
			}
			logger.Print("All Longhorn volumes and nodes are healthy.")

			logger.Print("Environment is ready for the Longhorn migration.")
			return nil
		},
	}
}

// scaleDownReplicas scales down the number of replicas for all volumes to 1. Returns a bool indicating if any
// of the volumes were scaled down.
func scaleDownReplicas(ctx context.Context, logger *log.Logger, cli client.Client) (bool, error) {
	var l1b1Volumes lhv1b1.VolumeList
	if err := cli.List(ctx, &l1b1Volumes, client.InNamespace(longhornNamespace)); err != nil {
		return false, fmt.Errorf("error listing longhorn volumes: %w", err)
	}

	var volumesToScale []lhv1b1.Volume
	for _, volume := range l1b1Volumes.Items {
		if volume.Spec.NumberOfReplicas == 1 {
			logger.Printf("Volume %s already has 1 replica, skipping.", volume.Name)
			continue
		}
		volumesToScale = append(volumesToScale, volume)
	}

	if len(volumesToScale) == 0 {
		return false, nil
	}

	for _, volume := range volumesToScale {
		logger.Printf("Scaling down replicas for volume %s.", volume.Name)
		for {
			nsn := types.NamespacedName{Namespace: longhornNamespace, Name: volume.Name}
			var updatedVolume lhv1b1.Volume
			if err := cli.Get(ctx, nsn, &updatedVolume); err != nil {
				return false, fmt.Errorf("error getting volume %s: %w", volume.Name, err)
			}

			if updatedVolume.Annotations == nil {
				updatedVolume.Annotations = map[string]string{}
			}
			if _, ok := updatedVolume.Annotations[pvmigrateScaleDownAnnotation]; !ok {
				updatedVolume.Annotations[pvmigrateScaleDownAnnotation] = strconv.Itoa(updatedVolume.Spec.NumberOfReplicas)
			}
			updatedVolume.Spec.NumberOfReplicas = 1
			if err := cli.Update(ctx, &updatedVolume); err != nil {
				if errors.IsConflict(err) {
					time.Sleep(time.Second)
					continue
				}
				return false, fmt.Errorf("error updating replicas for volume %s: %w", volume.Name, err)
			}
			break
		}
	}

	logger.Printf("Waiting %v for Longhorn volume replicas to scale down.", scaleDownReplicasWaitTime)
	time.Sleep(scaleDownReplicasWaitTime)
	return true, nil
}

// unhealthyVolumes returns a list of attached volumes that are not in a healthy state.
func unhealthyVolumes(ctx context.Context, logger *log.Logger, cli client.Client) ([]string, error) {
	var volumes lhv1b1.VolumeList
	if err := cli.List(ctx, &volumes, client.InNamespace(longhornNamespace)); err != nil {
		return nil, fmt.Errorf("error listing volumes: %w", err)
	}
	var result []string
	for _, volume := range volumes.Items {
		logger.Printf("Checking health of volume %s.", volume.Name)
		if volume.Status.State != lhv1b1.VolumeStateAttached || isVolumeHealthy(volume) {
			continue
		}
		result = append(result, volume.Name)
	}
	return result, nil
}

// isVolumeHealthy returns true if the volume is in a healthy state.
func isVolumeHealthy(vol lhv1b1.Volume) bool {
	for _, cond := range vol.Status.Conditions {
		if cond.Type != lhv1b1.VolumeConditionTypeScheduled {
			continue
		}
		if cond.Status == lhv1b1.ConditionStatusTrue {
			break
		}
		return false
	}
	return vol.Status.Robustness == lhv1b1.VolumeRobustnessHealthy
}

// unhealthyNodes returns a list of nodes that are not in a healthy state.
func unhealthyNodes(ctx context.Context, logger *log.Logger, cli client.Client) ([]string, error) {
	var longhornNodes lhv1b1.NodeList
	if err := cli.List(ctx, &longhornNodes); err != nil {
		return nil, fmt.Errorf("error listing longhorn nodes: %w", err)
	}
	var result []string
	for _, node := range longhornNodes.Items {
		logger.Printf("Checking health of node %s.", node.Name)
		if healthy, err := isNodeHealthy(ctx, cli, node); err != nil {
			return nil, fmt.Errorf("error checking node health: %w", err)
		} else if !healthy {
			result = append(result, node.Name)
		}
	}
	return result, nil
}

// isNodeHealthy returns true if the node is in a healthy state.
func isNodeHealthy(ctx context.Context, cli client.Client, node lhv1b1.Node) (bool, error) {
	if !nodeIs(lhv1b1.NodeConditionTypeReady, node) {
		return false, nil
	}
	if !nodeIs(lhv1b1.NodeConditionTypeSchedulable, node) {
		return false, nil
	}
	if !disksAre(lhv1b1.DiskConditionTypeReady, node.Status.DiskStatus) {
		return false, nil
	}
	if !disksAre(lhv1b1.DiskConditionTypeSchedulable, node.Status.DiskStatus) {
		return false, nil
	}
	if over, err := disksAreOvercommited(ctx, cli, node.Status.DiskStatus); err != nil {
		return false, fmt.Errorf("error checking disk overcommit: %w", err)
	} else if over {
		return false, nil
	}
	return true, nil
}

// disksAreOvercommited returns true if any disk in the node is overcommited.
func disksAreOvercommited(ctx context.Context, cli client.Client, disks map[string]*lhv1b1.DiskStatus) (bool, error) {
	var config lhv1b1.Setting
	nsn := client.ObjectKey{Name: overProvisioningSetting, Namespace: longhornNamespace}
	if err := cli.Get(ctx, nsn, &config); err != nil {
		return false, fmt.Errorf("error getting over provisioning setting: %w", err)
	}

	value, err := strconv.Atoi(config.Value)
	if err != nil {
		return false, fmt.Errorf("error parsing overcommit setting: %w", err)
	}
	pct := float64(value) / 100
	for _, disk := range disks {
		max := float64(disk.StorageAvailable) * pct
		if disk.StorageScheduled >= int64(max) {
			return true, nil
		}
	}
	return false, nil
}

// disksAre returns true if all disks are in the given condition.
func disksAre(condition string, disks map[string]*lhv1b1.DiskStatus) bool {
	for _, disk := range disks {
		for _, cond := range disk.Conditions {
			if cond.Type != condition {
				continue
			}
			return cond.Status == lhv1b1.ConditionStatusTrue
		}
	}
	return false
}

// nodeIs returns true if the node is in the given condition.
func nodeIs(condition string, node lhv1b1.Node) bool {
	for _, cond := range node.Status.Conditions {
		if cond.Type != condition {
			continue
		}
		return cond.Status == lhv1b1.ConditionStatusTrue
	}
	return false
}
