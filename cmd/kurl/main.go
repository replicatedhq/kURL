package main

import (
	"context"
	"log"
	"os"

	"github.com/replicatedhq/kurl/pkg/cli"
)

func main() {
	ctx := context.Background()
	kurlCLI, err := cli.NewKurlCLI()
	if err != nil {
		log.Fatal(err)
	}
	err = cli.NewKurlCmd(kurlCLI).ExecuteContext(ctx)
	if err != nil {
		os.Exit(1)
	}
}
