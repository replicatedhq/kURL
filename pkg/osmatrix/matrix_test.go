package osmatrix

import (
	"os"
	"path/filepath"
	"testing"
)

// TestGoldenMatrixSnapshot is the Testgrid coverage-matrix no-regression guard
// (replicatedhq/kURL#6081): it recomputes the per-test set of excluded OS ids
// from the committed testgrid specs and asserts it equals the frozen snapshot.
// The OS-matrix refactor may re-author unsupportedOSIDs lists (comments,
// ordering) but must never change WHICH (spec × OS) combinations run. If this
// fails after an intentional matrix change, regenerate the snapshot with:
//
//	go run ./cmd/os-matrix-gen snapshot > pkg/osmatrix/testdata/matrix-snapshot.txt
func TestGoldenMatrixSnapshot(t *testing.T) {
	root := repoRoot(t)
	got, err := MatrixSnapshot(filepath.Join(root, "testgrid", "specs"))
	if err != nil {
		t.Fatalf("MatrixSnapshot: %v", err)
	}
	wantPath := filepath.Join(root, "pkg", "osmatrix", "testdata", "matrix-snapshot.txt")
	want, err := os.ReadFile(wantPath)
	if err != nil {
		t.Fatalf("read snapshot: %v", err)
	}
	if got != string(want) {
		t.Errorf("Testgrid coverage matrix changed vs frozen snapshot.\n" +
			"If intentional, regenerate: go run ./cmd/os-matrix-gen snapshot > pkg/osmatrix/testdata/matrix-snapshot.txt")
	}
}
