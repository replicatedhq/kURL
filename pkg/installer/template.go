package installer

import (
	"bytes"
	"reflect"
	"text/template"

	"github.com/Masterminds/sprig"
	"github.com/pkg/errors"
	clusterv1beta1 "github.com/replicatedhq/kurlkinds/pkg/apis/cluster/v1beta1"
)

// TemplateData holds the data needed to run kURL templates
type TemplateData struct {
	Installer      clusterv1beta1.Installer
	IsPrimary      bool
	IsJoin         bool
	IsUpgrade      bool
	IsCluster      bool
	PrimaryHosts   []string
	SecondaryHosts []string
	RemoteHosts    []string
}

// ExecuteTemplate runs go templates to determine what preflights need to be run etc
func ExecuteTemplate(name, text string, data TemplateData) ([]byte, error) {
	zeroNilStructFields(&data.Installer.Spec)
	t, err := template.New(name).Funcs(sprig.TxtFuncMap()).Delims("{{kurl", "}}").Parse(text)
	if err != nil {
		return nil, errors.Wrap(err, "parse")
	}
	b := bytes.NewBuffer(nil)
	err = t.Execute(b, data)
	return b.Bytes(), errors.Wrap(err, "execute")
}

func zeroNilStructFields(v interface{}) {
	valueOf := reflect.ValueOf(v)
	typeOf := reflect.TypeOf(v)
	if valueOf.Kind() != reflect.Ptr || valueOf.IsNil() {
		return
	}
	if valueOf.Elem().Kind() != reflect.Struct {
		return
	}
	for i := 0; i < typeOf.Elem().NumField(); i++ {
		switch typeOf.Elem().Field(i).Type.Kind() {
		case reflect.Ptr:
			if !valueOf.Elem().Field(i).IsNil() {
				continue
			}
			ptr := reflect.New(valueOf.Elem().Field(i).Type())
			p2 := ptr.Elem()
			ptr.Elem().Set(reflect.New(p2.Type().Elem()))
			valueOf.Elem().Field(i).Set(p2)
		}
	}
}
