package main

import (
	"fmt"

	"github.com/replicatedhq/kurl/pkg/version"
	"github.com/replicatedhq/pvmigrate/pkg/migrate"
)

func main() {
	fmt.Printf("Running pvmigrate build:\n")
	version.Print()

	migrate.Cli()
}
