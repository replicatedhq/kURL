package version

import (
	"fmt"
)

// NOTE: these variables are injected at build time

var (
	gitSHA, buildTime string
)

func Print() {
	fmt.Printf("sha=%s\ntime=%s\n", gitSHA, buildTime)
}
