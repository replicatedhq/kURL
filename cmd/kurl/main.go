package main

import (
	"context"
	"log"
	"os"

	"github.com/pkg/errors"
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
		if errors.Is(err, cli.ErrWarn) {
			os.Exit(3)
		}
		os.Exit(1)
	}
}
