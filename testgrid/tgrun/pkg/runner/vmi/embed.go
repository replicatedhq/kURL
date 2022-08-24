package vmi

import (
	_ "embed" // my justification is https://golang.org/pkg/embed/
)

//go:embed embed/runcmd.sh
var runcmdSh []byte

//go:embed embed/common.sh
var commonSh []byte

//go:embed embed/secondarynodecmd.sh
var secondarynodecmd []byte

//go:embed embed/primarynodecmd.sh
var primarynodecmd []byte

//go:embed embed/mainscript.sh
var mainscript []byte

//go:embed embed/testhelpers.sh
var testHelpers []byte

//go:embed embed/finalizelogs.sh
var finalizeLogs []byte
