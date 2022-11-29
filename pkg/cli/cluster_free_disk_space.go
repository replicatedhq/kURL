package cli

import (
	"bytes"
	"fmt"
	"log"

	"github.com/spf13/cobra"
	v1 "k8s.io/api/storage/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"

	rookcli "github.com/rook/rook/pkg/client/clientset/versioned"

	clusterspace "github.com/replicatedhq/kurl/pkg/cluster/space"
)

const (
	// defaultOpenEBSPodImage is the image used during disk free check for openebs storage.
	// this is the same image used by the pvmigrate project, it may be any image containing
	// 'df' and 'cat' commands.
	defaultOpenEBSPodImage          = "eeacms/rsync:2.3"
	isDefaultStorageClassAnnotation = "storageclass.kubernetes.io/is-default-class"
	openEBSLocalProvisioner         = "openebs.io/local"
	rookRBDProvisioner              = "rook-ceph.rbd.csi.ceph.com"
	rookCephFSProvisioner           = "rook-ceph.cephfs.csi.ceph.com"
)

// NewClusterCheckFreeDiskSpaceCmd returns a command that is capable of reporting back the amount of free space in the cluster
// for a provided storage class.
func NewClusterCheckFreeDiskSpaceCmd(cli CLI) *cobra.Command {
	var forStorageClass, openEBSImage, openEBSNode string
	logbuf := bytes.NewBuffer(nil)
	logger := log.New(logbuf, "", 0)
	k8sConfig := config.GetConfigOrDie()
	clientSet := kubernetes.NewForConfigOrDie(k8sConfig)
	rookClientSet := rookcli.NewForConfigOrDie(k8sConfig)

	cmd := &cobra.Command{
		Use:          "check-free-disk-space",
		Long:         fmt.Sprintf("Returns the amount of free disk space (in bytes) for a given storage class\nSupported storage provisioners: %s, %s, %s", openEBSLocalProvisioner, rookRBDProvisioner, rookCephFSProvisioner),
		Example:      "kurl cluster check-free-disk-space --storageclass openebs --openebs-node-name node0 --openebs-image ubuntu:latest",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) (err error) {
			classes, err := clientSet.StorageV1().StorageClasses().List(cmd.Context(), metav1.ListOptions{})
			if err != nil {
				return fmt.Errorf("failed to list cluster storage classes: %w", err)
			}

			var selectedClass *v1.StorageClass
			for _, class := range classes.Items {
				val, ok := class.Annotations[isDefaultStorageClassAnnotation]
				if ok && val == "true" && forStorageClass == "" {
					selectedClass = &class
					logger.Printf("Selected default storage class %q", selectedClass.Name)
					break
				}

				if class.Name == forStorageClass {
					selectedClass = &class
					logger.Printf("Selected storage class %q", selectedClass.Name)
					break
				}
			}

			if selectedClass == nil {
				if forStorageClass == "" {
					return fmt.Errorf("failed to find default storage class")
				}
				return fmt.Errorf("failed to find storage class %q", forStorageClass)
			}

			switch selectedClass.Provisioner {
			case openEBSLocalProvisioner:
				freeSpaceGetter, err := clusterspace.NewOpenEBSFreeDiskSpaceGetter(clientSet, logger, openEBSImage, selectedClass.Name)
				if err != nil {
					fmt.Print(logbuf.String())
					return fmt.Errorf("failed to start openebs free space getter: %w", err)
				}

				volumes, err := freeSpaceGetter.OpenEBSVolumes(cmd.Context())
				if err != nil {
					fmt.Print(logbuf.String())
					return fmt.Errorf("failed to get openebs free space: %w", err)
				}

				for node, volume := range volumes {
					if openEBSNode == "" {
						fmt.Printf("%d\t%s\n", volume.Free, node)
						continue
					}

					if node != openEBSNode {
						logger.Printf("Skipping node %q", node)
						continue
					}

					fmt.Printf("%d\n", volume.Free)
					return nil
				}

				if openEBSNode != "" {
					fmt.Print(logbuf.String())
					return fmt.Errorf("failed to collect openebs free space: node %q not found", openEBSNode)
				}
				return nil

			case rookCephFSProvisioner, rookRBDProvisioner:
				freeSpaceGetter, err := clusterspace.NewRookFreeDiskSpaceGetter(clientSet, rookClientSet, selectedClass.Name)
				if err != nil {
					return fmt.Errorf("failed to start rook free space getter: %w", err)
				}

				space, err := freeSpaceGetter.GetFreeSpace(cmd.Context())
				if err != nil {
					return fmt.Errorf("failed to get rook free space: %w", err)
				}

				fmt.Println(space)
				return nil

			default:
				return fmt.Errorf("provisioner %q is not supported", selectedClass.Provisioner)
			}
		},
	}

	cmd.Flags().StringVar(&forStorageClass, "storageclass", "", "Inform the storage class name for which to check the free disk space. If not informed the default storage will be used.")
	cmd.Flags().StringVar(&openEBSImage, "openebs-image", defaultOpenEBSPodImage, fmt.Sprintf("The image used by OpenEBS disk free evaluation pod. If not informed the default image used is %s", defaultOpenEBSPodImage))
	cmd.Flags().StringVar(&openEBSNode, "openebs-node-name", "", "Show OpenEBS free disk space only for provided node.")
	return cmd
}
