// Command os-matrix-gen renders kURL's OS-keyed artifacts from the single-source
// registry (os-matrix.yaml) and, in check mode, verifies committed generated
// files are not stale.
//
// Usage:
//
//	os-matrix-gen generate   # write generated files
//	os-matrix-gen check      # exit non-zero if any generated file is stale
//
// Flags:
//
//	-matrix   path to the registry (default: os-matrix.yaml)
//	-root     repo root the generated paths are relative to (default: ".")
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/replicatedhq/kurl/pkg/osmatrix"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "os-matrix-gen:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	fs := flag.NewFlagSet("os-matrix-gen", flag.ContinueOnError)
	matrixPath := fs.String("matrix", "os-matrix.yaml", "path to the os-matrix registry")
	root := fs.String("root", ".", "repo root that generated paths are relative to")
	if err := fs.Parse(args); err != nil {
		return err
	}

	cmd := fs.Arg(0)
	if cmd == "" {
		return fmt.Errorf("usage: os-matrix-gen [generate|check] [-matrix path] [-root dir]")
	}

	// snapshot does not need the registry; it reads the committed testgrid specs.
	if cmd == "snapshot" {
		snap, err := osmatrix.MatrixSnapshot(filepath.Join(*root, "testgrid", "specs"))
		if err != nil {
			return err
		}
		fmt.Print(snap)
		return nil
	}

	m, err := osmatrix.Load(*matrixPath)
	if err != nil {
		return err
	}

	switch cmd {
	case "generate":
		changed, err := m.Write(*root)
		if err != nil {
			return err
		}
		if len(changed) == 0 {
			fmt.Println("os-matrix: generated files already up to date")
			return nil
		}
		for _, p := range changed {
			fmt.Println("wrote", p)
		}
		return nil

	case "check":
		stale, err := m.Check(*root)
		if err != nil {
			return err
		}
		if len(stale) == 0 {
			fmt.Println("### SUCCESS: generated OS-matrix artifacts are up to date ###")
			return nil
		}
		fmt.Fprintln(os.Stderr, "### ERROR: generated OS-matrix artifacts are stale. Run `make generate-os-matrix` and commit. ###")
		for _, p := range stale {
			fmt.Fprintln(os.Stderr, "  stale:", filepath.Clean(p))
		}
		return fmt.Errorf("%d generated file(s) out of date", len(stale))

	default:
		return fmt.Errorf("unknown command %q (want generate or check)", cmd)
	}
}
