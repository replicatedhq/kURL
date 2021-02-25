package main

import (
	"context"
	"os"

	"github.com/replicatedhq/kurl/pkg/cli"
)

func main() {
	ctx := context.Background()
	err := cli.RootCmd().ExecuteContext(ctx)
	if err != nil {
		os.Exit(1)
	}
}
