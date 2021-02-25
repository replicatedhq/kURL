package preflight

import _ "embed"

//go:embed assets/host-preflights.yaml
var builtin string

func Builtin() string {
	return builtin
}
