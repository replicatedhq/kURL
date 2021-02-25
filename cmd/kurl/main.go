package main

import (
	"context"
	"os"

	"github.com/replicatedhq/kurl/pkg/cli"
)

func main() {
	ctx := context.Background()
	kurlCLI := cli.NewKurlCLI()
	err := cli.NewRootCmd(kurlCLI).ExecuteContext(ctx)
	if err != nil {
		os.Exit(1)
	}
}
