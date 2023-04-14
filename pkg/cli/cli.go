package cli

import (
	"io"
	"log"
	"os"

	"github.com/chzyer/readline"
	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/pkg/preflight"
	"github.com/spf13/afero"
	"github.com/spf13/viper"
)

// CLI contains the required methods for a kurl CLI
type CLI interface {
	GetViper() *viper.Viper
	GetFS() afero.Fs
	GetReadline() *readline.Instance
	GetHostPreflightRunner() preflight.RunnerHost
	GetClusterPreflightRunner() preflight.RunnerCluster
	Stdout() io.Writer
	Stderr() io.Writer
	Logger() *log.Logger
	DebugLogger() *log.Logger
}

// KurlCLI is the real implementation of the kurl CLI
type KurlCLI struct {
	fs                     afero.Fs
	readline               *readline.Instance
	preflightClusterRunner *preflight.RunnerClusterPreflight
	preflightHostRunner    *preflight.RunnerHostPreflight
	stdout                 io.Writer
	stderr                 io.Writer
}

// NewKurlCLI builds a real kurl CLI object
func NewKurlCLI() (*KurlCLI, error) {
	rl, err := readline.New("")
	if err != nil {
		return nil, errors.Wrap(err, "new readline")
	}
	return &KurlCLI{
		fs:                     afero.NewOsFs(),
		readline:               rl,
		preflightHostRunner:    new(preflight.RunnerHostPreflight),
		preflightClusterRunner: new(preflight.RunnerClusterPreflight),
		stdout:                 os.Stdout,
		stderr:                 os.Stderr,
	}, nil
}

// GetViper returns the global viper instance
func (cli *KurlCLI) GetViper() *viper.Viper {
	return viper.GetViper()
}

// GetFS returns the FS that should be used with this CLI
func (cli *KurlCLI) GetFS() afero.Fs {
	return cli.fs
}

// GetReadline returns readline, which is used for interacting with terminals
func (cli *KurlCLI) GetReadline() *readline.Instance {
	return cli.readline
}

// GetHostPreflightRunner returns the runner for preflight checks
func (cli *KurlCLI) GetHostPreflightRunner() preflight.RunnerHost {
	return cli.preflightHostRunner
}

// GetClusterPreflightRunner returns the runner for preflight checks
func (cli *KurlCLI) GetClusterPreflightRunner() preflight.RunnerCluster {
	return cli.preflightClusterRunner
}

// Stdout returns the writer that writes to stdout unless it's been overridden
func (cli *KurlCLI) Stdout() io.Writer {
	return cli.stdout
}

// SetStdout overrides the writer that writes to stdout
func (cli *KurlCLI) SetStdout(w io.Writer) {
	cli.stdout = w
}

// Stderr returns the writer that writes to stderr unless it's been overridden
func (cli *KurlCLI) Stderr() io.Writer {
	return cli.stderr
}

// SetStderr overrides the writer that writes to stderr
func (cli *KurlCLI) SetStderr(w io.Writer) {
	cli.stdout = w
}

const (
	logDebugFlag   = "debug"
	logDebugPrefix = "DEBUG: "
)

// Logger returns the logger that should be used for standard log output.
// Logger logs to stderr.
func (cli *KurlCLI) Logger() *log.Logger {
	return log.New(cli.stderr, "", log.LstdFlags)
}

// DebugLogger returns the logger that should be used for debug level output.
// DebugLogger logs to stderr.
func (cli *KurlCLI) DebugLogger() *log.Logger {
	if cli.GetViper().GetBool(logDebugFlag) {
		return log.New(cli.stderr, logDebugPrefix, log.LstdFlags)
	}
	return log.New(io.Discard, "", 0)
}
