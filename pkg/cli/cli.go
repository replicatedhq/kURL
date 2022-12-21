package cli

import (
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
	GetPreflightRunner() preflight.Runner
}

// KurlCLI is the real implementation of the kurl CLI
type KurlCLI struct {
	fs              afero.Fs
	readline        *readline.Instance
	preflightRunner *preflight.PreflightRunner
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

// GetPreflightRunner returns the runner for preflight checks
func (cli *KurlCLI) GetPreflightRunner() preflight.Runner {
	return cli.preflightRunner
}

// NewKurlCLI builds a real kurl CLI object
func NewKurlCLI() (*KurlCLI, error) {
	rl, err := readline.New("")
	if err != nil {
		return nil, errors.Wrap(err, "new readline")
	}
	return &KurlCLI{
		fs:              afero.NewOsFs(),
		readline:        rl,
		preflightRunner: new(preflight.PreflightRunner),
	}, nil
}
