package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// TestFlagsHonoredAfterSubcommand guards the fix for the "post-command flags are
// ignored" finding: `-matrix`/`-root` placed AFTER the subcommand token must be
// parsed. We point -matrix at a path that does not exist and assert the load
// error references THAT path — proving the flag after the subcommand took effect
// (a top-level flag.Parse would ignore it and fall back to the default
// os-matrix.yaml, producing a different path in the error).
func TestFlagsHonoredAfterSubcommand(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "custom-matrix.yaml")

	for _, cmd := range []string{"generate", "check"} {
		t.Run(cmd, func(t *testing.T) {
			err := run([]string{cmd, "-matrix", missing})
			if err == nil {
				t.Fatalf("%s -matrix %s: expected error for missing registry", cmd, missing)
			}
			if !strings.Contains(err.Error(), "custom-matrix.yaml") {
				t.Errorf("%s: flag after subcommand ignored; error does not reference -matrix path: %v", cmd, err)
			}
		})
	}
}

// TestMatrixDefaultsRelativeToRoot guards the fix for the "root uses the wrong
// matrix" finding: with -root set and no -matrix, the registry must be resolved
// under that root, not the current working directory. We point -root at an empty
// temp dir (which has no os-matrix.yaml) and assert the load error references a
// path UNDER that root — proving the command did not silently fall back to the
// CWD's os-matrix.yaml (which exists in this repo checkout and would otherwise
// let it check/write the target root using the wrong matrix).
func TestMatrixDefaultsRelativeToRoot(t *testing.T) {
	root := t.TempDir()
	want := filepath.Join(root, "os-matrix.yaml")

	for _, cmd := range []string{"generate", "check"} {
		t.Run(cmd, func(t *testing.T) {
			err := run([]string{cmd, "-root", root})
			if err == nil {
				t.Fatalf("%s -root %s: expected error for missing registry under root", cmd, root)
			}
			if !strings.Contains(err.Error(), want) {
				t.Errorf("%s: matrix not resolved under -root; error does not reference %q: %v", cmd, want, err)
			}
		})
	}
}

// TestUnknownSubcommandErrors ensures an unrecognized subcommand is reported
// rather than silently parsed as a flag.
func TestUnknownSubcommandErrors(t *testing.T) {
	err := run([]string{"bogus"})
	if err == nil || !strings.Contains(err.Error(), "unknown command") {
		t.Errorf("expected unknown command error, got: %v", err)
	}
}

// TestNoArgsUsage ensures invoking with no subcommand returns usage.
func TestNoArgsUsage(t *testing.T) {
	err := run(nil)
	if err == nil || !strings.Contains(err.Error(), "usage:") {
		t.Errorf("expected usage error with no args, got: %v", err)
	}
}
