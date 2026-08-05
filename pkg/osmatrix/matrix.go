package osmatrix

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// This file computes the Testgrid coverage matrix as the per-test set of
// excluded OS ids, independent of comments and ordering. Freezing this set (see
// TestGoldenMatrixSnapshot) is the acceptance guard for replicatedhq/kURL#6081:
// the OS-matrix refactor — especially the unsupportedOSIDs generation (bucket 2)
// — must not change WHICH (spec × OS) combinations Testgrid runs, only how the
// exclusion lists are authored.

type testSpecEntry struct {
	Name             string   `yaml:"name"`
	UnsupportedOSIDs []string `yaml:"unsupportedOSIDs"`
}

// MatrixSnapshot returns a stable, canonical text snapshot of the Testgrid
// coverage matrix: one line per test spec entry, listing its sorted set of
// excluded OS ids. Comments and list ordering within unsupportedOSIDs do not
// affect the snapshot — only the set of excluded ids does.
func MatrixSnapshot(specsDir string) (string, error) {
	entries, err := os.ReadDir(specsDir)
	if err != nil {
		return "", fmt.Errorf("read specs dir: %w", err)
	}
	var files []string
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".yaml") {
			continue
		}
		if strings.HasPrefix(name, "os-") { // OS pool files, not test specs
			continue
		}
		files = append(files, name)
	}
	sort.Strings(files)

	var lines []string
	for _, f := range files {
		data, err := os.ReadFile(filepath.Join(specsDir, f))
		if err != nil {
			return "", fmt.Errorf("read %s: %w", f, err)
		}
		var specs []testSpecEntry
		if err := yaml.Unmarshal(data, &specs); err != nil {
			return "", fmt.Errorf("parse %s: %w", f, err)
		}
		for i, s := range specs {
			ids := append([]string(nil), s.UnsupportedOSIDs...)
			sort.Strings(ids)
			lines = append(lines, fmt.Sprintf("%s\t%d\t%s\t%s", f, i, s.Name, strings.Join(ids, ",")))
		}
	}
	sort.Strings(lines)
	return strings.Join(lines, "\n") + "\n", nil
}
