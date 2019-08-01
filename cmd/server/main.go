package main

import (
	"log"
	"os"
	"path/filepath"

	"github.com/replicatedhq/kurl/pkg/build"
	"github.com/replicatedhq/kurl/pkg/server"
)

func main() {
	os.Getenv("GOPATH")
	dir := filepath.Join(os.Getenv("GOPATH"), "src/github.com/replicatedhq/kurl")
	live := true
	builder, err := build.NewBuilder(dir, live)
	if err != nil {
		log.Panic(err)
	}

	server := server.New(builder, filepath.Join(dir, "dist"))

	server.Run(":8080")
}
