package cli

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"syscall"

	storagev1 "k8s.io/api/storage/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"

	"code.cloudfoundry.org/bytefmt"
	rookcli "github.com/rook/rook/pkg/client/clientset/versioned"
	"github.com/spf13/cobra"

	clusterspace "github.com/replicatedhq/kurl/pkg/cluster/space"
)

const (
	// defaultOpenEBSPodImage is the image used during disk free check for openebs storage. this is the same image used by the
	// pvmigrate project, it may be any image containing 'df' and 'cat' commands.
	defaultOpenEBSPodImage          = "eeacms/rsync:2.3"
	isDefaultStorageClassAnnotation = "storageclass.kubernetes.io/is-default-class"
	openEBSLocalProvisioner         = "openebs.io/local"
	rookRBDProvisioner              = "rook-ceph.rbd.csi.ceph.com"
	rookCephFSProvisioner           = "rook-ceph.cephfs.csi.ceph.com"
)

// getStorageClassByName returns a storage class by its name. if storageClassName is empty then this function returns the default storage
// class for the cluster.
func getStorageClassByName(ctx context.Context, kubeCli kubernetes.Interface, storageClassName string) (*storagev1.StorageClass, error) {
	classes, err := kubeCli.StorageV1().StorageClasses().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to list cluster storage classes: %w", err)
	}

	for _, class := range classes.Items {
		val, ok := class.Annotations[isDefaultStorageClassAnnotation]
		if ok && val == "true" && storageClassName == "" {
			return &class, nil
		}

		if class.Name == storageClassName {
			return &class, nil
		}
	}

	if storageClassName == "" {
		return nil, fmt.Errorf("failed to find the default storage class")
	}
	return nil, fmt.Errorf("failed to find storage class %q", storageClassName)
}

// hasEnoughSpace compares if free space is bigger than the requested space. returns a user friendly string representing the output
// and a bool indicating if there is or not enough room. this function is an auxiliar function so we don't need to keep concatenating
// the output strings in the evaluateOpenEBSFreeSpace function.
func hasEnoughSpace(node string, free, requested int64) (string, bool) {
	requestedString := bytefmt.ByteSize(uint64(requested))
	freeString := bytefmt.ByteSize(uint64(free))
	if free >= requested {
		message := fmt.Sprintf("Node %s has %s available", node, freeString)
		if requested > 0 {
			message = fmt.Sprintf("%s (requested %s)", message, requestedString)
		}
		return message, true
	}
	return fmt.Sprintf("Not enough space on node %s (requested %s, available %s)", node, requestedString, freeString), false
}

// evaluateOpenEBSFreeSpace checks how much space is available in a storage class backed by openEBSLocalProvisioner. biggerThan is
// used to check if there is enough room in one node (if onNode != "") or in all nodes (onNode == ""). onNode is the node name, image
// is the image to be used by the openebs disk free checker pod while the biggerThan is expressed in bytes.
func evaluateOpenEBSFreeSpace(ctx context.Context, kubeCli kubernetes.Interface, image, scname, onNode string, biggerThan int64, debug bool) error {
	logger := log.New(io.Discard, "", 0)
	if debug {
		logger = log.New(os.Stderr, "", 0)
	}

	freeSpaceGetter, err := clusterspace.NewOpenEBSFreeDiskSpaceGetter(kubeCli, logger, image, scname)
	if err != nil {
		return fmt.Errorf("failed to start openebs free space getter: %w", err)
	}

	volumes, err := freeSpaceGetter.OpenEBSVolumes(ctx)
	if err != nil {
		return fmt.Errorf("failed to get openebs free space: %w", err)
	}

	successOutput := bytes.NewBuffer(nil)
	for node, volume := range volumes {
		var msg string
		var hasSpace bool
		if node == onNode {
			if msg, hasSpace = hasEnoughSpace(node, volume.Free, biggerThan); !hasSpace {
				return fmt.Errorf(msg)
			}
			fmt.Println(msg)
			return nil
		}

		if onNode == "" {
			if msg, hasSpace = hasEnoughSpace(node, volume.Free, biggerThan); !hasSpace {
				return fmt.Errorf(msg)
			}
			fmt.Fprintf(successOutput, "%s\n", msg)
			continue
		}
	}

	if onNode != "" {
		return fmt.Errorf("failed to collect openebs free space: node %q not found", onNode)
	}

	fmt.Print(successOutput.String())
	return nil
}

// evaluateOpenEBSFreeSpace checks how much space is available in a storage class backed by rookRBDProvisioner or rookCephFSProvisioner. biggerThan
// is used to compare if there is enough room.
func evaluateRookFreeSpace(ctx context.Context, kubeCli kubernetes.Interface, rookCli rookcli.Interface, scname string, requested int64) error {
	freeSpaceGetter, err := clusterspace.NewRookFreeDiskSpaceGetter(kubeCli, rookCli, scname)
	if err != nil {
		return fmt.Errorf("failed to start rook free space getter: %w", err)
	}

	free, err := freeSpaceGetter.GetFreeSpace(ctx)
	if err != nil {
		return fmt.Errorf("failed to get rook free space: %w", err)
	}

	requestedString := bytefmt.ByteSize(uint64(requested))
	freeString := bytefmt.ByteSize(uint64(free))
	if free < requested {
		return fmt.Errorf("not enough space on rook (requested %s, available %s)", requestedString, freeString)
	}

	message := fmt.Sprintf("Available disk space found in rook: %s", freeString)
	if requested > 0 {
		message = fmt.Sprintf("%s (requested %s)", message, requestedString)
	}
	fmt.Println(message)
	return nil
}

// NewClusterCheckFreeDiskSpaceCmd returns a command that is capable of reporting back the amount of free space in the cluster for a provided storage class.
func NewClusterCheckFreeDiskSpaceCmd(_ CLI) *cobra.Command {
	var forStorageClass, openEBSImage, openEBSNode, biggerThanString string
	var biggerThanBytes int64
	var clientSet kubernetes.Interface
	var rookClientSet rookcli.Interface
	var selectedClass *storagev1.StorageClass
	var debug bool

	cmd := &cobra.Command{
		Use:          "check-free-disk-space",
		Short:        "List and analyse the available disk space for a given Storage Class.",
		SilenceUsage: true,
		Example: fmt.Sprintf(""+
			"In the following examples 'openebs' is the name of a storage class backed by the %s storage provisioner while 'rook' is the name of a storage\n"+
			"class backed by the %s or %s storage provisioners.\n\n"+
			"# reports the available space in rook\n"+
			"kurl cluster check-free-disk-space --storageclass rook\n\n"+
			"# reports the available space in all nodes\n"+
			"kurl cluster check-free-disk-space --storageclass openebs\n\n"+
			"# checks if there is 10G available on node node0\n"+
			"kurl cluster check-free-disk-space --storageclass openebs --openebs-node-name node0 --openebs-image ubuntu:latest --bigger-than 10G\n\n"+
			"# checks if there is 10G available on all nodes in the cluster\n"+
			"kurl cluster check-free-disk-space --storageclass openebs --bigger-than 10G\n"+
			"# checks if there is 20G available in the cluster on the default storage class\n"+
			"kurl cluster check-free-disk-space --bigger-than 20G\n",
			openEBSLocalProvisioner, rookRBDProvisioner, rookCephFSProvisioner,
		),
		Long: fmt.Sprintf(""+
			"This program returns the amount of free disk space (in bytes) for a given storage class or compares if there is enough space to hold a certain\n"+
			"amount of data (--bigger-than). For OpenEBS, when no --bigger-than flag is provided, this program returns a list of nodes and their respective\n"+
			"free space, while for Rook storage only the available space is returned. When --bigger-than flag is used this program sets the exit code to zero\n"+
			"if the space available is bigger than the quantity provided. For OpenEBS, if no node has been provided through --openebs-node-name the exit code\n"+
			"will be zero only if all nodes free space are bigger than the provided quantity (see Examples section for more details).\n\n"+
			"Supports the following storage provisioners: %s, %s, %s",
			openEBSLocalProvisioner, rookRBDProvisioner, rookCephFSProvisioner,
		),
		PreRunE: func(cmd *cobra.Command, _ []string) error {
			k8sConfig, err := config.GetConfig()
			if err != nil {
				return fmt.Errorf("failed to read kubernetes configuration: %w", err)
			}

			clientSet, err = kubernetes.NewForConfig(k8sConfig)
			if err != nil {
				return fmt.Errorf("failed to create kubernetes client: %w", err)
			}

			rookClientSet, err = rookcli.NewForConfig(k8sConfig)
			if err != nil {
				return fmt.Errorf("failed to create rook client: %w", err)
			}

			debug, err = cmd.Flags().GetBool("debug")
			if err != nil {
				return fmt.Errorf("failed to read persistent debug flag: %w", err)
			}

			if selectedClass, err = getStorageClassByName(cmd.Context(), clientSet, forStorageClass); err != nil {
				return err
			}

			if biggerThanString == "" {
				return nil
			}

			parsed, err := resource.ParseQuantity(biggerThanString)
			if err != nil {
				return fmt.Errorf("failed to parse %s as a quantity: %w", biggerThanString, err)
			}
			biggerThanBytes = parsed.Value()

			return nil
		},
		RunE: func(cmd *cobra.Command, _ []string) error {
			ctx, cancel := signal.NotifyContext(cmd.Context(), syscall.SIGTERM, syscall.SIGINT)
			defer cancel()

			switch selectedClass.Provisioner {
			case openEBSLocalProvisioner:
				return evaluateOpenEBSFreeSpace(ctx, clientSet, openEBSImage, selectedClass.Name, openEBSNode, biggerThanBytes, debug)

			case rookCephFSProvisioner, rookRBDProvisioner:
				return evaluateRookFreeSpace(ctx, clientSet, rookClientSet, selectedClass.Name, biggerThanBytes)

			default:
				fmt.Printf("Provisioner %q is not supported, unable to determine free space.\n", selectedClass.Provisioner)
				return nil
			}
		},
	}

	cmd.Flags().StringVar(&forStorageClass, "storageclass", "", "Inform the storage class name for which to check the free disk space. If not informed the default storage will be used.")
	cmd.Flags().StringVar(&biggerThanString, "bigger-than", "", "Compares if the cluster free disk space is bigger than the provided value. Accepts the same format as used when defining storage requests in Kubernetes (e.g. 10G, 5Gi, 500M).")
	cmd.Flags().StringVar(&openEBSImage, "openebs-image", defaultOpenEBSPodImage, fmt.Sprintf("The image used by OpenEBS disk free evaluation pod. If not informed the default image used is %s", defaultOpenEBSPodImage))
	cmd.Flags().StringVar(&openEBSNode, "openebs-node-name", "", "Evaluates OpenEBS free disk space only for the provided node name.")
	return cmd
}
