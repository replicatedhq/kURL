package k8sutil

import (
	"context"
	"fmt"
	"io"
	"log"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// PodUsesPVC returs true if provided pod has provided pvc among its volumes.
func PodUsesPVC(pod corev1.Pod, pvc corev1.PersistentVolumeClaim) bool {
	if pod.Namespace != pvc.Namespace {
		return false
	}

	for _, vol := range pod.Spec.Volumes {
		if vol.PersistentVolumeClaim == nil {
			continue
		}
		if vol.PersistentVolumeClaim.ClaimName != pvc.Name {
			continue
		}
		return true
	}

	return false
}

// RunEphemeralPod starts provided pod and waits until it finishes. the values returned are the
// pod logs, its last status, and an error. returned logs and pod status may be nil depending on
// the type of failure. the pod is deleted at the end.
func RunEphemeralPod(ctx context.Context, cli kubernetes.Interface, logger *log.Logger, timeout time.Duration, pod *corev1.Pod) (map[string][]byte, *corev1.PodStatus, error) {
	podidx := fmt.Sprintf("%s/%s", pod.Namespace, pod.Name)
	pod, err := cli.CoreV1().Pods(pod.Namespace).Create(ctx, pod, metav1.CreateOptions{})
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create pod %s: %w", podidx, err)
	}

	defer func() {
		if err = cli.CoreV1().Pods(pod.Namespace).Delete(
			context.Background(), pod.Name, metav1.DeleteOptions{},
		); err != nil {
			logger.Printf("failed to delete pod %s: %s", podidx, err)
		}
	}()

	startedAt := time.Now()
	var lastPodStatus corev1.PodStatus
	var hasTimedOut bool
	for {
		var gotPod *corev1.Pod
		if gotPod, err = cli.CoreV1().Pods(pod.Namespace).Get(
			ctx, pod.Name, metav1.GetOptions{},
		); err != nil {
			return nil, nil, fmt.Errorf("failed getting pod %s: %w", podidx, err)
		}

		lastPodStatus = gotPod.Status
		if gotPod.Status.Phase == corev1.PodSucceeded {
			break
		}

		time.Sleep(time.Second)
		if time.Now().After(startedAt.Add(timeout)) {
			hasTimedOut = true
			break
		}
	}

	logs := map[string][]byte{}
	for _, container := range pod.Spec.Containers {
		options := &corev1.PodLogOptions{Container: container.Name}
		podlogs, err := cli.CoreV1().Pods(pod.Namespace).GetLogs(pod.Name, options).Stream(ctx)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to get pod log stream: %w", err)
		}

		defer func(stream io.ReadCloser) {
			if err := stream.Close(); err != nil {
				logger.Printf("failed to close pod log stream: %s", err)
			}
		}(podlogs)

		output, err := io.ReadAll(podlogs)
		if err != nil {
			return nil, &lastPodStatus, fmt.Errorf("failed to read pod logs: %w", err)
		}

		logs[container.Name] = output
	}

	if hasTimedOut {
		return logs, &lastPodStatus, fmt.Errorf("timeout waiting for the pod")
	}

	return logs, &lastPodStatus, nil
}
