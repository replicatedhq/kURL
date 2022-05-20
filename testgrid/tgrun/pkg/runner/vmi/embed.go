package vmi

import (
	_ "embed" // my justification is https://golang.org/pkg/embed/
)

//go:embed embed/runcmd.sh
var runcmdSh string

//go:embed embed/common.sh
var commonSh string

//go:embed embed/secondarynodecmd.sh
var secondarynodecmd string
