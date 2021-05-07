package installer

import (
	"bytes"
	"text/template"

	"github.com/Masterminds/sprig"
	"github.com/pkg/errors"
	clusterv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
)

type TemplateData struct {
	Installer      clusterv1beta1.Installer
	IsPrimary      bool
	IsJoin         bool
	IsUpgrade      bool
	PrimaryHosts   []string
	SecondaryHosts []string
	RemoteHosts    []string
}

func ExecuteTemplate(name, text string, data TemplateData) ([]byte, error) {
	t, err := template.New(name).Funcs(sprig.TxtFuncMap()).Delims("{{kurl", "}}").Parse(text)
	if err != nil {
		return nil, errors.Wrap(err, "parse")
	}
	b := bytes.NewBuffer(nil)
	err = t.Execute(b, data)
	return b.Bytes(), errors.Wrap(err, "execute")
}
