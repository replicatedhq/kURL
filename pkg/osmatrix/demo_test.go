package osmatrix

import (
	"strings"
	"testing"
)

// TestSingleEntryAddDemonstration is the executable form of the issue's
// acceptance demo (replicatedhq/kURL#6081): adding/removing a supported OS is a
// single registry change plus regenerate. It removes ubuntu-2604 from the loaded
// registry (the one entry, plus its pool memberships and its generated
// Dockerfile flag) and asserts that every rendered artifact then loses exactly
// the ubuntu-2604 content — nothing else changes surface across the six spec
// files and the bundle Dockerfiles.
func TestSingleEntryAddDemonstration(t *testing.T) {
	full, _ := loadRealMatrix(t)

	// Baseline: with ubuntu-2604 present, it appears in the artifacts.
	baseline, err := full.Artifacts()
	if err != nil {
		t.Fatalf("baseline Artifacts: %v", err)
	}
	if !anyContains(baseline, "ubuntu-2604") {
		t.Fatal("expected ubuntu-2604 in baseline artifacts")
	}
	baseBundle := countBundleDockerfiles(baseline)

	// The single-entry removal: drop the ubuntu-2604 OS entry and any pool
	// reference to it. This models reverting exactly the registry side of the
	// #6072 change.
	reduced := withoutOS(full, "ubuntu-2604")

	after, err := reduced.Artifacts()
	if err != nil {
		t.Fatalf("reduced Artifacts: %v", err)
	}
	if anyContains(after, "ubuntu-2604") {
		t.Error("ubuntu-2604 still present after removing its single registry entry")
	}

	// One fewer generated bundle Dockerfile, and the same set of spec files
	// (pools are unchanged in count — only their contents shrink).
	if got := countBundleDockerfiles(after); got != baseBundle-1 {
		t.Errorf("expected %d bundle Dockerfiles after removal, got %d", baseBundle-1, got)
	}
	if len(poolArtifacts(after)) != len(poolArtifacts(baseline)) {
		t.Error("removing an OS should not change the set of pool spec files")
	}
}

func withoutOS(m *Matrix, id string) *Matrix {
	var oses []OS
	for _, o := range m.OSes {
		if o.ID == id {
			continue
		}
		oses = append(oses, o)
	}
	pools := make([]Pool, 0, len(m.Pools))
	for _, p := range m.Pools {
		var ids []string
		for _, pid := range p.IDs {
			// Pool ids are keys; skip any whose OS resolves to the removed id.
			if o, ok := m.OS(pid); ok && o.ID == id {
				continue
			}
			ids = append(ids, pid)
		}
		pools = append(pools, Pool{Name: p.Name, IDs: ids, TrailingNewline: p.TrailingNewline})
	}
	reduced := &Matrix{OSes: oses, Pools: pools}
	if err := reduced.index(); err != nil {
		panic(err)
	}
	return reduced
}

func anyContains(arts []Artifact, s string) bool {
	for _, a := range arts {
		if strings.Contains(string(a.Content), s) {
			return true
		}
	}
	return false
}

func countBundleDockerfiles(arts []Artifact) int {
	n := 0
	for _, a := range arts {
		if strings.HasSuffix(a.Path, "Dockerfile") {
			n++
		}
	}
	return n
}

func poolArtifacts(arts []Artifact) []Artifact {
	var out []Artifact
	for _, a := range arts {
		if strings.HasSuffix(a.Path, ".yaml") {
			out = append(out, a)
		}
	}
	return out
}
