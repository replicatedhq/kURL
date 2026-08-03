package osmatrix

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

// repoRoot walks up from the test's working directory to the directory holding
// go.mod, so the golden tests can locate the real registry and committed specs
// regardless of where `go test` is invoked from.
func repoRoot(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatalf("could not find repo root (go.mod) from working dir")
		}
		dir = parent
	}
}

func loadRealMatrix(t *testing.T) (*Matrix, string) {
	t.Helper()
	root := repoRoot(t)
	m, err := Load(filepath.Join(root, "os-matrix.yaml"))
	if err != nil {
		t.Fatalf("load real os-matrix.yaml: %v", err)
	}
	return m, root
}

// TestGoldenPools proves that every testgrid OS-spec file rendered from the
// registry is byte-identical to the committed file. This is the no-regression
// gate: the single source cannot silently change installer/testgrid behavior.
func TestGoldenPools(t *testing.T) {
	m, root := loadRealMatrix(t)

	for _, p := range m.Pools {
		t.Run(p.Name, func(t *testing.T) {
			got, err := m.RenderPool(p.Name)
			if err != nil {
				t.Fatalf("RenderPool %s: %v", p.Name, err)
			}
			specPath := filepath.Join(root, "testgrid", "specs", p.Name+".yaml")
			want, err := os.ReadFile(specPath)
			if err != nil {
				t.Fatalf("read committed spec %s: %v", specPath, err)
			}
			if !bytes.Equal(got, want) {
				t.Errorf("rendered %s.yaml does not match committed file.\n"+
					"got  (%d bytes): %q\nwant (%d bytes): %q",
					p.Name, len(got), truncate(got), len(want), truncate(want))
			}
		})
	}
}

func truncate(b []byte) string {
	const maxLen = 400
	if len(b) > maxLen {
		return string(b[:maxLen]) + "...(truncated)"
	}
	return string(b)
}
