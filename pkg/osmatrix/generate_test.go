package osmatrix

import (
	"os"
	"path/filepath"
	"testing"
)

func TestArtifactsCoverAllPools(t *testing.T) {
	m, err := Parse([]byte(testFixture))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	arts, err := m.Artifacts()
	if err != nil {
		t.Fatalf("Artifacts: %v", err)
	}
	if len(arts) != len(m.Pools) {
		t.Fatalf("expected one artifact per pool (%d), got %d", len(m.Pools), len(arts))
	}
	want := filepath.Join("testgrid", "specs", "os-latest.yaml")
	if arts[0].Path != want {
		t.Errorf("expected first artifact path %q, got %q", want, arts[0].Path)
	}
}

func TestWriteThenCheckRoundTrips(t *testing.T) {
	m, err := Parse([]byte(testFixture))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	root := t.TempDir()

	// First write reports every artifact as changed (files did not exist).
	changed, err := m.Write(root)
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if len(changed) != len(m.Pools) {
		t.Fatalf("first Write should create %d files, changed %d", len(m.Pools), len(changed))
	}

	// Freshly written tree is in sync.
	stale, err := m.Check(root)
	if err != nil {
		t.Fatalf("Check: %v", err)
	}
	if len(stale) != 0 {
		t.Fatalf("expected no stale files after Write, got %v", stale)
	}

	// Second write is idempotent: nothing changes.
	changed, err = m.Write(root)
	if err != nil {
		t.Fatalf("second Write: %v", err)
	}
	if len(changed) != 0 {
		t.Errorf("second Write should be idempotent, changed %v", changed)
	}
}

func TestCheckDetectsDrift(t *testing.T) {
	m, err := Parse([]byte(testFixture))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	root := t.TempDir()
	if _, err := m.Write(root); err != nil {
		t.Fatalf("Write: %v", err)
	}

	// Corrupt one generated file.
	target := filepath.Join(root, "testgrid", "specs", "os-latest.yaml")
	if err := os.WriteFile(target, []byte("tampered\n"), 0o644); err != nil {
		t.Fatalf("tamper: %v", err)
	}
	stale, err := m.Check(root)
	if err != nil {
		t.Fatalf("Check: %v", err)
	}
	if len(stale) != 1 || stale[0] != filepath.Join("testgrid", "specs", "os-latest.yaml") {
		t.Fatalf("expected exactly os-latest.yaml stale, got %v", stale)
	}

	// A missing generated file is also drift.
	if err := os.Remove(target); err != nil {
		t.Fatalf("remove: %v", err)
	}
	stale, err = m.Check(root)
	if err != nil {
		t.Fatalf("Check after remove: %v", err)
	}
	if len(stale) != 1 {
		t.Fatalf("expected missing file reported stale, got %v", stale)
	}
}
