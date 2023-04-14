package cli

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"os/signal"
	"strings"
	"syscall"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/cli-runtime/pkg/printers"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
	"sigs.k8s.io/kustomize/api/types"

	"github.com/google/uuid"
	"github.com/replicatedhq/plumber/v2"
	"github.com/spf13/cobra"

	"github.com/replicatedhq/kurl/pkg/k8sutil"
	"github.com/replicatedhq/kurl/pkg/static/nodes_connectivity"
)

var usageExamples = `
# Test if all nodes can reach all other nodes using tcp in port 6472.
kurl netutil nodes-connectivity --port 6472 --proto tcp
# Test if all nodes can reach all other nodes using udp in port 7788.
kurl netutil nodes-connectivity --port 7788 --proto udp
`

const (
	listenersSelector = "name=nodes-connectivity-listener"
	pingerSelector    = "name=nodes-connectivity-pinger"
)

type logLine struct {
	message string
	err     error
}

type nodeConnectivityOptions struct {
	printf    func(string, ...interface{})
	namespace string
	proto     string
	attempts  int
	cliset    kubernetes.Interface
	image     string
	port      int32
	cli       client.Client
	wait      time.Duration
}

func newNetutilNodesConnectivity(_ CLI) *cobra.Command {
	var opts nodeConnectivityOptions
	cmd := &cobra.Command{
		Use:     "nodes-connectivity",
		Short:   "Tests if all nodes can reach all other nodes using the provided protocol in the provided port",
		Example: usageExamples,
		PreRunE: func(cmd *cobra.Command, args []string) error {
			if opts.port == 0 {
				return fmt.Errorf("--port flag is required.")
			}
			opts.proto = strings.ToUpper(opts.proto)
			proto := corev1.Protocol(opts.proto)
			if proto != corev1.ProtocolTCP && proto != corev1.ProtocolUDP {
				return fmt.Errorf("--protocol must be either tcp or udp.")
			}
			opts.wait = time.Second
			if corev1.Protocol(opts.proto) == corev1.ProtocolUDP {
				opts.wait = 5 * time.Second
			}
			// now that all input args have been validated we can silence the usage print upon error.
			cmd.SilenceUsage = true
			cfg, err := config.GetConfig()
			if err != nil {
				return fmt.Errorf("failed to get kubernetes config: %w", err)
			}
			cli, err := client.New(cfg, client.Options{})
			if err != nil {
				return fmt.Errorf("failed to create kubernetes client: %w", err)
			}
			opts.cli = cli
			cliset, err := kubernetes.NewForConfig(config.GetConfigOrDie())
			if err != nil {
				return fmt.Errorf("failed to create kubernetes client set: %s", err)
			}
			opts.cliset = cliset
			opts.printf = cmd.Printf
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			ctx, cancel := signal.NotifyContext(cmd.Context(), syscall.SIGTERM, syscall.SIGINT)
			defer cancel()

			defer func() {
				ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
				defer cancel()
				if err := deleteListeners(ctx, opts); err != nil {
					opts.printf("Failed to delete DaemonSet listeners overlay: %s\n", err)
				}
				if err := deletePinger(ctx, opts); err != nil {
					opts.printf("Failed to delete pinger job: %s\n", err)
				}
			}()

			opts.printf("Testing intra nodes connectivity using port %d/%s.\n", opts.port, opts.proto)
			opts.printf("Connection between all nodes will be attempted, this can take a while.\n")
			if err := deployListenersDaemonset(ctx, opts); err != nil {
				return fmt.Errorf("Failed to deploy listeners: %w", err)
			}

			if err := testNodesConnectivity(ctx, opts); err != nil {
				return fmt.Errorf("Failed to test nodes connectivity: %w", err)
			}

			opts.printf("All nodes can reach all nodes using %s protocol in port %d.\n", opts.proto, opts.port)
			return nil
		},
	}
	cmd.Flags().StringVar(&opts.proto, "proto", "tcp", "The protocol to use for the test (either tcp or udp).")
	cmd.Flags().StringVar(&opts.namespace, "namespace", "default", "The namespace to use during the test.")
	cmd.Flags().StringVar(&opts.image, "image", "replicated/kurl-util:latest", "The image to use for the test (image must contain bash, nc and echo).")
	cmd.Flags().Int32Var(&opts.port, "port", 0, "The port to use for the test.")
	cmd.Flags().IntVar(&opts.attempts, "udp-attempts", 5, "The number of connection attempts when using udp.")
	return cmd
}

// printDaemonsetStatus prints the status of the daemonset. this function also prints the pod statuses.
func printDaemonsetStatus(ctx context.Context, opts nodeConnectivityOptions, ds *appsv1.DaemonSet) {
	opts.printf("DaemonSet failed to deploy, that can possibly mean that port %d (%s) is in use.\n", opts.port, opts.proto)
	buffer := bytes.NewBuffer([]byte("\n"))
	table := &metav1.Table{}
	request := opts.cliset.AppsV1().RESTClient().Get().
		Resource("daemonsets").
		Namespace(opts.namespace).
		Name(ds.Name).
		SetHeader("Accept", "application/json;as=Table;v=v1beta1;g=meta.k8s.io")
	if err := request.Do(ctx).Into(table); err != nil {
		opts.printf("Failed to get DaemonSet: %s\n", err)
		return
	}
	printer := printers.NewTablePrinter(printers.PrintOptions{})
	printer.PrintObj(table, buffer)
	request = opts.cliset.CoreV1().RESTClient().Get().
		Resource("pods").
		Namespace(opts.namespace).
		Param("labelSelector", listenersSelector).
		Param("limit", "500").
		SetHeader("Accept", "application/json;as=Table;v=v1;g=meta.k8s.io")
	if err := request.Do(ctx).Into(table); err != nil {
		opts.printf("Failed to list DaemonSet pods: %s\n", err)
		return
	}
	printer = printers.NewTablePrinter(printers.PrintOptions{Wide: true, WithKind: true})
	buffer.WriteString("\n")
	printer.PrintObj(table, buffer)
	scanner := bufio.NewScanner(buffer)
	scanner.Split(bufio.ScanLines)
	for scanner.Scan() {
		opts.printf("%s\n", scanner.Text())
	}
	opts.printf("\n")
}

// deployListenersDaemonset deploys a daemonset that will run a pod that listens for udp or tcp packets,
// on port 9999. a service is created to expose the daemonset pods, this service is of type nodeport and
// binds to nodeConnectivityOptions.port port.
func deployListenersDaemonset(ctx context.Context, opts nodeConnectivityOptions) error {
	opts.printf("Deploying node connectivity listeners DaemonSet.\n")
	options := []plumber.Option{
		plumber.WithKustomizeMutator(kustomizeMutator(opts)),
		plumber.WithObjectMutator(func(ctx context.Context, obj client.Object) error {
			if ds, ok := obj.(*appsv1.DaemonSet); ok {
				tolerations, err := k8sutil.TolerationsForAllNodes(ctx, opts.cliset)
				if err != nil {
					return fmt.Errorf("failed to build tolerations: %v", err)
				}
				ds.Spec.Template.Spec.Tolerations = tolerations
				ds.Spec.Template.Spec.Containers[0].Env = []corev1.EnvVar{
					{Name: "PORT", Value: fmt.Sprintf("%d", opts.port)},
				}
			}
			return nil
		}),
		plumber.WithPostApplyAction(func(ctx context.Context, obj client.Object) error {
			if ds, ok := obj.(*appsv1.DaemonSet); ok {
				err := k8sutil.WaitForDaemonsetRollout(ctx, opts.cliset, ds, time.Minute)
				if err != nil {
					printDaemonsetStatus(ctx, opts, ds)
					return fmt.Errorf("failed to wait for DaemonSet rollout: %w", err)
				}
			}
			return nil
		}),
	}
	overlay := fmt.Sprintf("%s-listeners", strings.ToLower(opts.proto))
	renderer := plumber.NewRenderer(opts.cli, nodes_connectivity.Static, options...)
	if err := renderer.Apply(ctx, overlay); err != nil {
		return fmt.Errorf("failed to create listeners daemonset: %w", err)
	}
	opts.printf("Listeners DaemonSet deployed successfully.\n")
	return nil
}

func attachToListenersPods(ctx context.Context, opts nodeConnectivityOptions, pods []corev1.Pod) <-chan logLine {
	var out = make(chan logLine)
	for _, pod := range pods {
		go func(pod corev1.Pod) {
			logopts := &corev1.PodLogOptions{Follow: true}
			req := opts.cliset.CoreV1().Pods(opts.namespace).GetLogs(pod.Name, logopts)
			stream, err := req.Stream(ctx)
			if err != nil {
				out <- logLine{err: fmt.Errorf("failed to get logs for pod %s: %w", pod.Name, err)}
				return
			}
			defer stream.Close()

			scanner := bufio.NewScanner(stream)
			scanner.Split(bufio.ScanLines)
			for scanner.Scan() {
				out <- logLine{message: scanner.Text()}
			}
			if err := scanner.Err(); err != nil {
				out <- logLine{err: fmt.Errorf("failed to read logs for pod %s: %w", pod.Name, err)}
			}
		}(pod)
	}
	return out
}

// kustomizeMutator returns a kustomize mutator that sets the namespace and image.
func kustomizeMutator(opts nodeConnectivityOptions) plumber.KustomizeMutator {
	image := types.Image{Name: "nodes-connectivity-image", NewName: opts.image}
	return func(ctx context.Context, kz *types.Kustomization) error {
		kz.Namespace = opts.namespace
		kz.Images = append(kz.Images, image)
		return nil
	}
}

// deletePinger delete the pinger job and all its related pods.
func deletePinger(ctx context.Context, opts nodeConnectivityOptions) error {
	opt := plumber.WithKustomizeMutator(kustomizeMutator(opts))
	renderer := plumber.NewRenderer(opts.cli, nodes_connectivity.Static, opt)
	if err := renderer.Delete(ctx, "pinger"); err != nil {
		return fmt.Errorf("failed to delete pinger job: %w", err)
	}
	// XXX unfortunately we have to remove all pods manually.
	pods, err := k8sutil.ListPodsBySelector(ctx, opts.cliset, opts.namespace, pingerSelector)
	if err != nil {
		return fmt.Errorf("failed to get pinger pods: %w", err)
	}
	for _, pod := range pods.Items {
		if err := opts.cli.Delete(ctx, &pod); err != nil {
			return fmt.Errorf("failed to delete pod %s: %v", pod.Name, err)
		}
	}
	return nil
}

// connectNodeFromNode creates a job that inherit the provided pod affinity and tolerations. this attempts to send an uuid
// through a network connection to the target ip and configured port/protocol. returns the sent uuid.
func connectNodeFromNode(ctx context.Context, opts nodeConnectivityOptions, model corev1.Pod, targetIP string) (string, error) {
	id := uuid.New().String()
	options := []plumber.Option{
		plumber.WithKustomizeMutator(kustomizeMutator(opts)),
		plumber.WithObjectMutator(func(ctx context.Context, obj client.Object) error {
			if job, ok := obj.(*batchv1.Job); ok {
				env := []corev1.EnvVar{
					{Name: "NODEIP", Value: targetIP},
					{Name: "NODEPORT", Value: fmt.Sprint(opts.port)},
					{Name: "UUID", Value: id},
				}
				args := corev1.EnvVar{Name: "NCARGS", Value: "-w 2"}
				if corev1.Protocol(opts.proto) == corev1.ProtocolUDP {
					args = corev1.EnvVar{Name: "NCARGS", Value: "-uw 2"}
				}
				env = append(env, args)
				job.Spec.Template.Spec.Affinity = model.Spec.Affinity
				//job.Spec.Template.Spec.Tolerations = model.Spec.Tolerations
				job.Spec.Template.Spec.Containers[0].Env = env
			}
			return nil
		}),
		plumber.WithPostApplyAction(func(ctx context.Context, obj client.Object) error {
			if job, ok := obj.(*batchv1.Job); ok {
				if _, err := k8sutil.WaitForJob(ctx, opts.cliset, job, time.Minute); err != nil {
					return fmt.Errorf("failed to create job: %s", err)
				}
			}
			return nil
		}),
	}
	renderer := plumber.NewRenderer(opts.cli, nodes_connectivity.Static, options...)
	if err := renderer.Apply(ctx, "pinger"); err != nil {
		return "", fmt.Errorf("failed to apply pinger job: %w", err)
	}
	return id, nil
}

// testNodesConnectivity tests the connectivity between the cluster nodes.
func testNodesConnectivity(ctx context.Context, opts nodeConnectivityOptions) error {
	pods, err := k8sutil.ListPodsBySelector(ctx, opts.cliset, opts.namespace, listenersSelector)
	if err != nil {
		return fmt.Errorf("failed to get listener pods: %w", err)
	}
	receiver := attachToListenersPods(ctx, opts, pods.Items)
	var nodes corev1.NodeList
	if err := opts.cli.List(ctx, &nodes); err != nil {
		return fmt.Errorf("failed to list nodes: %w", err)
	}
	for _, node := range nodes.Items {
		if err := connectToNodeFromPods(ctx, opts, node, receiver); err != nil {
			return fmt.Errorf("node %s: %w", node.Name, err)
		}
	}
	return nil
}

// connectToNodeFromPods connects to the provided node by spawning pods in all other nodes and verifying they can reach
// the destination ip address and port.
func connectToNodeFromPods(ctx context.Context, opts nodeConnectivityOptions, node corev1.Node, receiver <-chan logLine) error {
	pods, err := k8sutil.ListPodsBySelector(ctx, opts.cliset, opts.namespace, listenersSelector)
	if err != nil {
		return fmt.Errorf("failed to get listener pods: %w", err)
	}
	dstIP, err := k8sutil.NodeInternalIP(node)
	if err != nil {
		return fmt.Errorf("failed to determine node %s ip: %w", node.Name, err)
	}
	attempts := opts.attempts
	if corev1.Protocol(opts.proto) == corev1.ProtocolTCP {
		attempts = 1
	}
	for _, pod := range pods.Items {
		src, dst := pod.Spec.NodeName, node.Name
		if src == dst {
			continue
		}
		var success bool
		for i := 1; i <= attempts; i++ {
			opts.printf("Testing connection from %s to %s (%d/%d)\n", src, dst, i, attempts)
			id, err := connectNodeFromNode(ctx, opts, pod, dstIP)
			if err != nil {
				return fmt.Errorf("failed to connect node %s from node %s: %v", src, dst, err)
			}

			if err := deletePinger(ctx, opts); err != nil {
				return fmt.Errorf("failed to delete pinger job: %w", err)
			}

			select {
			case line := <-receiver:
				if line.err == nil {
					success = line.message == id
					break
				}
				return fmt.Errorf("failed to read listener pod output: %w", line.err)
			case <-time.After(opts.wait):
			}

			if success {
				opts.printf("Success, packet received.\n")
				break
			}
			retrying := "retrying."
			if i == attempts {
				retrying = "giving up."
			}
			opts.printf("Failed to connect from %s to %s, %s\n", src, dst, retrying)
		}

		if success {
			continue
		}
		opts.printf("\n")
		opts.printf("Attempt to connect from %s to %s on %d (%s) failed.\n", src, dst, opts.port, opts.proto)
		opts.printf("Please verify if the active network policies are not blocking the connection.\n")
		return fmt.Errorf("failed to connect from %s to %s", src, dst)
	}
	return nil
}

// deleteListeners deletes the listeners daemonset and service.
func deleteListeners(ctx context.Context, opts nodeConnectivityOptions) error {
	opt := plumber.WithKustomizeMutator(kustomizeMutator(opts))
	overlay := fmt.Sprintf("%s-listeners", strings.ToLower(opts.proto))
	renderer := plumber.NewRenderer(opts.cli, nodes_connectivity.Static, opt)
	if err := renderer.Delete(ctx, overlay); err != nil {
		return fmt.Errorf("failed to delete daemonset listeners overlay: %w", err)
	}
	return nil
}
