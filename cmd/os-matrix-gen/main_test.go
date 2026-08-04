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
