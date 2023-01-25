package cli

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"time"

	"github.com/spf13/cobra"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/config"

	lhv1b1 "github.com/longhorn/longhorn-manager/k8s/pkg/apis/longhorn/v1beta1"
)

var (
	scaleDownReplicasWaitTime = time.Minute
)

const (
	volumeReplicasAnnotation = "kurl.sh/volume-replica-count"
	longhornNamespace        = "longhorn-system"
	overProvisioningSetting  = "storage-over-provisioning-percentage"
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

func NewLonghornRollbackMigrationReplicas(_ CLI) *cobra.Command {
	return &cobra.Command{
		Use:          "rollback-migration-replicas",
		Short:        "Rollback Longhorn volume replicas to their original value.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			log.Print("Rolling back Longhorn volume replicas to their original value.")
			cli, err := client.New(config.GetConfigOrDie(), client.Options{})
			if err != nil {
				return fmt.Errorf("error creating client: %s", err)
			}
			lhv1b1.AddToScheme(cli.Scheme())

			var l1b1Volumes lhv1b1.VolumeList
			if err := cli.List(cmd.Context(), &l1b1Volumes, client.InNamespace(longhornNamespace)); err != nil {
				log.Fatalf("error listing longhorn volumes: %s", err)
			}

			for _, volume := range l1b1Volumes.Items {
				if _, ok := volume.Annotations[volumeReplicasAnnotation]; !ok {
					log.Printf("Volume %s has not been scaled down, skipping.", volume.Name)
					continue
				}

				replicas, err := strconv.Atoi(volume.Annotations[volumeReplicasAnnotation])
				if err != nil {
					log.Fatalf("error parsing replica count for volume %s: %s", volume.Name, err)
				}

				log.Printf("Rolling back volume %s to %d replicas.", volume.Name, replicas)
				delete(volume.Annotations, volumeReplicasAnnotation)
				volume.Spec.NumberOfReplicas = replicas
				if err := cli.Update(cmd.Context(), &volume); err != nil {
					log.Fatalf("error rolling back volume %s replicas: %s", volume.Name, err)
				}
			}
			log.Printf("Longhorn volumes have been rolled back to their original replica count.")
			return nil
		},
	}
}

func NewLonghornPrepareForMigration(_ CLI) *cobra.Command {
	return &cobra.Command{
		Use:          "prepare-for-migration",
		Short:        "Prepares Longhorn for migration to a different storage provisioner.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			log.Print("Preparing Longhorn deployment for migration.")
			cli, err := client.New(config.GetConfigOrDie(), client.Options{})
			if err != nil {
				return fmt.Errorf("error creating client: %s", err)
			}
			lhv1b1.AddToScheme(cli.Scheme())

			var scaledDown bool
			var nodes corev1.NodeList
			if err := cli.List(cmd.Context(), &nodes); err != nil {
				return fmt.Errorf("error listing kubernetes nodes: %s", err)
			} else if len(nodes.Items) == 1 {
				log.Print("Only one node found, scaling down the number of volume replicas to 1.")
				if scaledDown, err = scaleDownReplicas(cmd.Context(), cli); err != nil {
					return fmt.Errorf("error scaling down longhorn replicas: %s", err)
				}
			}

			unhealthy, err := unhealthyVolumes(cmd.Context(), cli)
			if err != nil {
				return fmt.Errorf("error assessing unhealthy volumes: %s", err)
			}

			if len(unhealthy) > 0 {
				log.Printf("The following Longhorn volumes are unhealthy:")
				for _, vol := range unhealthy {
					log.Printf(" - %s/%s", longhornNamespace, vol)
				}
				return fmt.Errorf("error preparing longhorn for migration: unhealthy volumes")
			}

			unhealthy, err = unhealthyNodes(cmd.Context(), cli)
			if err != nil {
				return fmt.Errorf("error assessing unhealthy Longhorn nodes: %s", err)
			}

			if len(unhealthy) > 0 {
				log.Printf("The following Longhorn nodes are unhealthy:")
				for _, node := range unhealthy {
					log.Printf(" - %s", node)
				}
				return fmt.Errorf("error preparing longhorn for migration: unhealthy nodes")
			}

			if scaledDown {
				log.Printf("Storage volumes have been scaled down to 1 replica for the migration.")
				log.Printf("If necessary, you can scale them back up to the original value with:")
				log.Printf("")
				log.Printf("$ kurl longhorn rollback-migration-replicas")
				log.Printf("")
			}
			log.Print("All Longhorn volumes and nodes are healthy, ready for migration.")
			return nil
		},
	}
}

// scaleDownReplicas scales down the number of replicas for all volumes to 1. Returns a bool indicating if any
// of the volumes were scaled down.
func scaleDownReplicas(ctx context.Context, cli client.Client) (bool, error) {
	var l1b1Volumes lhv1b1.VolumeList
	if err := cli.List(ctx, &l1b1Volumes, client.InNamespace(longhornNamespace)); err != nil {
		return false, fmt.Errorf("error listing longhorn volumes: %w", err)
	}

	var volumesToScale []lhv1b1.Volume
	for _, volume := range l1b1Volumes.Items {
		if volume.Spec.NumberOfReplicas == 1 {
			log.Printf("Volume %s already has 1 replica, skipping.", volume.Name)
			continue
		}
		volumesToScale = append(volumesToScale, volume)
	}

	if len(volumesToScale) == 0 {
		return false, nil
	}

	for _, volume := range volumesToScale {
		log.Printf("Scaling down replicas for volume %s.", volume.Name)
		if volume.Annotations == nil {
			volume.Annotations = map[string]string{}
		}
		if _, ok := volume.Annotations[volumeReplicasAnnotation]; !ok {
			volume.Annotations[volumeReplicasAnnotation] = strconv.Itoa(volume.Spec.NumberOfReplicas)
		}
		volume.Spec.NumberOfReplicas = 1
		if err := cli.Update(ctx, &volume); err != nil {
			return false, fmt.Errorf("error updating replicas for volume %s: %w", volume.Name, err)
		}
	}

	log.Printf("Awaiting %v for replicas to scale down.", scaleDownReplicasWaitTime)
	time.Sleep(scaleDownReplicasWaitTime)
	return true, nil
}

// unhealthyVolumes returns a list of attached volumes that are not in a healthy state.
func unhealthyVolumes(ctx context.Context, cli client.Client) ([]string, error) {
	var volumes lhv1b1.VolumeList
	if err := cli.List(ctx, &volumes, client.InNamespace(longhornNamespace)); err != nil {
		return nil, fmt.Errorf("error listing volumes: %w", err)
	}
	var result []string
	for _, volume := range volumes.Items {
		log.Printf("Checking health of volume %s.", volume.Name)
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
func unhealthyNodes(ctx context.Context, cli client.Client) ([]string, error) {
	var longhornNodes lhv1b1.NodeList
	if err := cli.List(ctx, &longhornNodes); err != nil {
		return nil, fmt.Errorf("error listing longhorn nodes: %w", err)
	}
	var result []string
	for _, node := range longhornNodes.Items {
		log.Printf("Checking health of node %s.", node.Name)
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
