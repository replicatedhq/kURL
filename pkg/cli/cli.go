package cli

import (
	"github.com/chzyer/readline"
	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/pkg/preflight"
	"github.com/spf13/afero"
	"github.com/spf13/viper"
)

type CLI interface {
	GetViper() *viper.Viper
	GetFS() afero.Fs
	GetReadline() *readline.Instance
	GetPreflightRunner() preflight.Runner
}

type KurlCLI struct {
	fs              afero.Fs
	readline        *readline.Instance
	preflightRunner *preflight.PreflightRunner
}

func (cli *KurlCLI) GetViper() *viper.Viper {
	return viper.GetViper()
}

func (cli *KurlCLI) GetFS() afero.Fs {
	return cli.fs
}

func (cli *KurlCLI) GetReadline() *readline.Instance {
	return cli.readline
}

func (cli *KurlCLI) GetPreflightRunner() preflight.Runner {
	return cli.preflightRunner
}

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
