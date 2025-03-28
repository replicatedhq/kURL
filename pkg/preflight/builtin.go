package preflight

import (
	_ "embed" // my justification is https://golang.org/pkg/embed/
)

//go:embed assets/host-preflights.yaml
var builtin string

// Builtin returns the default set of kURL host preflights
func Builtin() string {
	return builtin
}

//go:embed assets/preflights.yaml
var builtinCluster string

// BuiltinCluster returns the default set of kURL host preflights
func BuiltinCluster() string {
	return builtinCluster
}
