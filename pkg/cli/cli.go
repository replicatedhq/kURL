package cli

import (
	"os"

	isatty "github.com/mattn/go-isatty"
	"github.com/replicatedhq/kurl/pkg/preflight"
	"github.com/spf13/afero"
)

type CLI interface {
	GetFS() afero.Fs
	IsTerminal() bool
	GetPreflightRunner() preflight.Runner
}

type KurlCLI struct {
}

func (cli *KurlCLI) GetFS() afero.Fs {
	return afero.NewOsFs()
}

func (cli *KurlCLI) IsTerminal() bool {
	return isatty.IsTerminal(os.Stdout.Fd())
}

func (cli *KurlCLI) GetPreflightRunner() preflight.Runner {
	return new(preflight.PreflightRunner)
}

func NewKurlCLI() *KurlCLI {
	return &KurlCLI{}
}
