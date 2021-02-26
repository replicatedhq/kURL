package preflight

import (
	_ "embed" // my justification is https://golang.org/pkg/embed/
)

//go:embed assets/host-preflights.yaml
var builtin string

func Builtin() string {
	return builtin
}
