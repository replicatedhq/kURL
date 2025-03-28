package rook

import (
	"context"
	"fmt"
	"strings"

	"github.com/replicatedhq/kurl/pkg/k8sutil"
	"github.com/replicatedhq/kurl/pkg/rook/static"
	appsv1 "k8s.io/api/apps/v1"
	autoscalingv1 "k8s.io/api/autoscaling/v1"
	k8sErrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	corev1client "k8s.io/client-go/kubernetes/typed/core/v1"
	restclient "k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
	yaml "sigs.k8s.io/yaml"
)

// this is modified by unit test functions to add mock command/response entries
var execFunction func(coreClient corev1client.CoreV1Interface, clientConfig *restclient.Config, ns, pod, container string, command ...string) (int, string, string, error) = k8sutil.SyncExec

// this is the config used to exec commands in a pod
var conf *restclient.Config

// determine if the rook-ceph-toolbox deployment exists; if it does ensure scale is proper; if it does not create it with the rook image used by the operator
func startToolbox(ctx context.Context, client kubernetes.Interface) error {
	existingToolbox, err := client.AppsV1().Deployments("rook-ceph").Get(ctx, "rook-ceph-tools", metav1.GetOptions{})
	if err == nil {
		// toolbox exists
		if existingToolbox.Status.Replicas == 0 {
			// toolbox needs to be scaled up
			_, err = client.AppsV1().Deployments("rook-ceph").UpdateScale(ctx, "rook-ceph-tools", &autoscalingv1.Scale{Spec: autoscalingv1.ScaleSpec{Replicas: 1}}, metav1.UpdateOptions{})
			if err != nil {
				return fmt.Errorf("unable to scale up rook-ceph-tools deployment: %w", err)
			}

			err = awaitDeploymentScale(ctx, client, "rook-ceph", "rook-ceph-tools", 1)
			if err != nil {
				return fmt.Errorf("unable to wait for rook-ceph-tools to scale up: %w", err)
			}
		}

		return nil
	}
	if !k8sErrors.IsNotFound(err) {
		return fmt.Errorf("unable to determine rook-ceph-tools deployment status: %w", err)
	}

	out("The rook-ceph-toolbox deployment does not exist, starting it")

	image, err := operatorImage(ctx, client)
	if err != nil {
		return fmt.Errorf("unable to determine rook-ceph-operator image: %w", err)
	}

	fromYaml := appsv1.Deployment{}

	err = yaml.Unmarshal(static.Toolbox, &fromYaml)
	if err != nil {
		return fmt.Errorf("unable to parse static toolbox yaml: %w", err)
	}

	fromYaml.Spec.Template.Spec.Containers[0].Image = image

	_, err = client.AppsV1().Deployments("rook-ceph").Create(ctx, &fromYaml, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("unable to create rook-ceph-tools deployment: %w", err)
	}

	out("Waiting for rook-ceph-toolbox to start")

	err = awaitDeploymentScale(ctx, client, "rook-ceph", "rook-ceph-tools", 1)
	if err != nil {
		return fmt.Errorf("unable to wait for rook-ceph-tools to scale up: %w", err)
	}

	out("Started rook-ceph-toolbox deployment")

	return nil
}

// determine the current rook image
func operatorImage(ctx context.Context, client kubernetes.Interface) (string, error) {
	existingOperator, err := client.AppsV1().Deployments("rook-ceph").Get(ctx, "rook-ceph-operator", metav1.GetOptions{})
	if err != nil {
		return "", fmt.Errorf("unable to get rook-ceph-operator deployment: %w", err)
	}

	return existingOperator.Spec.Template.Spec.Containers[0].Image, nil
}

func cacheConfig() (*restclient.Config, error) {
	if conf != nil {
		return conf, nil
	}

	k8sConfig, err := config.GetConfig()
	if err != nil {
		return nil, fmt.Errorf("unable to get rest config: %w", err)
	}
	conf = k8sConfig

	return k8sConfig, nil
}

type runToolboxCommandExitCodeError struct {
	ExitCode      int
	PodName       string
	PrettyCommand string
	Stderr        string
}

func (e runToolboxCommandExitCodeError) Error() string {
	return fmt.Errorf("failed to run %q in %s with stderr %q with exit code %d", e.PrettyCommand, e.PodName, e.Stderr, e.ExitCode).Error()
}

// run a specified command in the toolbox, and return the output if the command ran, and an error otherwise
func runToolboxCommand(ctx context.Context, client kubernetes.Interface, inContainer []string) (string, string, error) {
	pods, err := client.CoreV1().Pods("rook-ceph").List(ctx, metav1.ListOptions{LabelSelector: "app=rook-ceph-tools"})
	if err != nil {
		return "", "", fmt.Errorf("unable to find rook-ceph-tools pod: %w", err)
	}
	if len(pods.Items) != 1 {
		podnames := []string{}
		for _, pod := range pods.Items {
			podnames = append(podnames, pod.Name)
		}

		return "", "", fmt.Errorf("found %d rook-ceph-tools pods, with names %q, expected 1", len(pods.Items), strings.Join(podnames, ", "))
	}

	prettyCmd := strings.Join(inContainer, " ")
	podName := pods.Items[0].Name
	k8sConfig, err := cacheConfig()
	if err != nil {
		return "", "", fmt.Errorf("unable to get rest config to exec in container: %w", err)
	}

	exitCode, stdout, stderr, err := execFunction(client.CoreV1(), k8sConfig, "rook-ceph", podName, pods.Items[0].Spec.Containers[0].Name, inContainer...)
	if err != nil {
		return "", "", fmt.Errorf("failed to run %q in %s: %w", prettyCmd, podName, err)
	}
	if exitCode != 0 {
		return stdout, stderr, runToolboxCommandExitCodeError{exitCode, podName, prettyCmd, stderr}
	}
	return stdout, stderr, nil
}
