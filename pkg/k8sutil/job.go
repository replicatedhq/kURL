package k8sutil

import (
	"context"
	"fmt"
	"io"
	"log"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/client-go/kubernetes"
)

// WaitForJob waits for a job to finish. returns a boolean indicating if the job succeeded.
func WaitForJob(ctx context.Context, cli kubernetes.Interface, job *batchv1.Job, timeout time.Duration) (bool, error) {
	var endAt = time.Now().Add(timeout)
	for {
		gotJob, err := cli.BatchV1().Jobs(job.Namespace).Get(ctx, job.Name, metav1.GetOptions{})
		if err != nil {
			return false, fmt.Errorf("failed getting job: %w", err)
		}

		switch {
		case gotJob.Status.Failed > 0:
			return false, nil
		case gotJob.Status.Succeeded > 0:
			return true, nil
		default:
			time.Sleep(time.Second)
		}

		if time.Now().After(endAt) {
			return false, fmt.Errorf("timeout waiting for job to finish")
		}
	}
}

// RunJob runs the provided job and waits until it finishes or the timeout is reached.
// returns the job's pod logs (indexed by container name) and the state of each of the
// containers (also indexed by container name).
func RunJob(ctx context.Context, cli kubernetes.Interface, logger *log.Logger, job *batchv1.Job, timeout time.Duration) (map[string][]byte, map[string]corev1.ContainerState, error) {
	job.Labels = AppendKurlLabels(job.Labels)
	job, err := cli.BatchV1().Jobs(job.Namespace).Create(ctx, job, metav1.CreateOptions{})
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create job: %w", err)
	}

	defer func() {
		propagation := metav1.DeletePropagationForeground
		deleteOpts := metav1.DeleteOptions{PropagationPolicy: &propagation}
		// Cleanup should use background context so as not to fail if context has already been canceled
		if err = cli.BatchV1().Jobs(job.Namespace).Delete(
			context.Background(), job.Name, deleteOpts,
		); err != nil {
			logger.Printf("failed to delete job: %s", err)
		}
	}()

	jobSucceeded, err := WaitForJob(ctx, cli, job, timeout)
	if err != nil {
		return nil, nil, err
	}

	listOptions := metav1.ListOptions{
		LabelSelector: labels.SelectorFromSet(job.Spec.Selector.MatchLabels).String(),
	}

	var pods *corev1.PodList
	if pods, err = cli.CoreV1().Pods(job.Namespace).List(ctx, listOptions); err != nil {
		return nil, nil, fmt.Errorf("failed to list pods for job: %w", err)
	} else if len(pods.Items) == 0 {
		return nil, nil, fmt.Errorf("pod for job not found")
	}

	jobPod := pods.Items[0]

	lastContainerStatuses := map[string]corev1.ContainerState{}
	for _, status := range jobPod.Status.ContainerStatuses {
		lastContainerStatuses[status.Name] = status.State
	}

	logs := map[string][]byte{}
	for _, container := range jobPod.Spec.Containers {
		options := &corev1.PodLogOptions{Container: container.Name}
		podLogs, err := cli.CoreV1().Pods(jobPod.Namespace).GetLogs(jobPod.Name, options).Stream(ctx)
		if err != nil && jobSucceeded {
			// if the job succeed to execute but there is an error to read the container logs we bail.
			return nil, nil, fmt.Errorf("failed to read container %s logs: %w", container.Name, err)
		} else if err != nil {
			message := fmt.Sprintf("failed to get container %s logs: %s", container.Name, err)
			logger.Print(message)
			logs[container.Name] = []byte(message)
			continue
		}

		defer func(stream io.ReadCloser) {
			if err := stream.Close(); err != nil {
				logger.Printf("failed to close pod log stream: %s", err)
			}
		}(podLogs)

		output, err := io.ReadAll(podLogs)
		if err != nil {
			return nil, lastContainerStatuses, fmt.Errorf("failed to read pod logs: %w", err)
		}

		logs[container.Name] = output
	}

	if !jobSucceeded {
		return logs, lastContainerStatuses, fmt.Errorf("job failed to execute")
	}
	return logs, lastContainerStatuses, nil
}
