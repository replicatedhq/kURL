package version

import (
	"fmt"
	"io"
)

// NOTE: these variables are injected at build time

var (
	version, gitSHA, buildTime string
)

func Print() {
	fmt.Printf("version=%s\nsha=%s\ntime=%s\n", version, gitSHA, buildTime)
}

func Fprint(w io.Writer) {
	fmt.Fprintf(w, "version=%s\nsha=%s\ntime=%s\n", version, gitSHA, buildTime)
}
