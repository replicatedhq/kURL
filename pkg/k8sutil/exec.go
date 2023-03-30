package k8sutil

import (
	"bytes"
	"context"
	"io"

	"k8s.io/client-go/util/exec"

	"github.com/pkg/errors"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/scheme"
	corev1client "k8s.io/client-go/kubernetes/typed/core/v1"
	restclient "k8s.io/client-go/rest"
	"k8s.io/client-go/tools/remotecommand"
)

type ExecOptions struct {
	StreamOptions

	Command []string

	CoreClient corev1client.CoreV1Interface
	Config     *restclient.Config
}

type StreamOptions struct {
	Namespace     string
	PodName       string
	ContainerName string
	TTY           bool
	In            io.Reader
	Out           io.Writer
	Err           io.Writer
}

// ExecContainer executes a remote execution against a pod. Returns exit code
// and error. The error will be non-nil if exit code is not 0.
func ExecContainer(ctx context.Context, opts ExecOptions, terminalSizeQueue remotecommand.TerminalSizeQueue) (int, error) {
	// TODO: handle tty, build TerminalSizeQueue from StreamOpts.In?
	// TODO: ctx

	req := opts.CoreClient.RESTClient().Post().
		Resource("pods").
		Name(opts.PodName).
		Namespace(opts.Namespace).
		SubResource("exec").
		Param("container", opts.ContainerName)
	req.VersionedParams(&corev1.PodExecOptions{
		Container: opts.ContainerName,
		Command:   opts.Command,
		Stdin:     opts.In != nil,
		Stdout:    opts.Out != nil,
		Stderr:    opts.Err != nil,
		TTY:       opts.TTY,
	}, runtime.NewParameterCodec(scheme.Scheme))

	executor, err := remotecommand.NewSPDYExecutor(opts.Config, "POST", req.URL())
	if err != nil {
		return 0, errors.Wrap(err, "create exec")
	}

	if err := executor.StreamWithContext(ctx, remotecommand.StreamOptions{
		Stdin:             opts.In,
		Stdout:            opts.Out,
		Stderr:            opts.Err,
		Tty:               opts.TTY,
		TerminalSizeQueue: terminalSizeQueue,
	}); err != nil {
		var exitCode int
		if err, ok := err.(exec.CodeExitError); ok {
			exitCode = err.Code
		}
		return exitCode, errors.Wrap(err, "stream exec")
	}
	return 0, nil
}

// SyncExec returns exitcode, stdout, stderr. A non-zero exit code from the command is not considered an error.
func SyncExec(coreClient corev1client.CoreV1Interface, clientConfig *restclient.Config, ns, pod, container string, command ...string) (int, string, string, error) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	opts := ExecOptions{
		CoreClient: coreClient,
		Config:     clientConfig,
		Command:    command,
		StreamOptions: StreamOptions{
			Namespace:     ns,
			PodName:       pod,
			ContainerName: container,
			Out:           &stdout,
			Err:           &stderr,
		},
	}
	exitCode, err := ExecContainer(context.TODO(), opts, nil)
	if exitCode != 0 {
		err = nil
	}

	return exitCode, stdout.String(), stderr.String(), err
}
