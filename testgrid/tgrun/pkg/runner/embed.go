package runner

import (
	_ "embed" // my justification is https://golang.org/pkg/embed/
)

//go:embed embed/runcmd.sh
var runcmdSh string
