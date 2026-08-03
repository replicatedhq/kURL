package osmatrix

import (
	"fmt"
	"os"
	"path/filepath"
)

// Artifact is one generated file: a repo-relative path and its rendered content.
type Artifact struct {
	// Path is relative to the repo root.
	Path    string
	Content []byte
}

// Artifacts returns every file rendered from the registry, in a stable order.
// This is the authoritative list consumed by both generation and the drift
// guard, so the two can never disagree about what is generated.
func (m *Matrix) Artifacts() ([]Artifact, error) {
	var out []Artifact
	for _, p := range m.Pools {
		content, err := m.RenderPool(p.Name)
		if err != nil {
			return nil, err
		}
		out = append(out, Artifact{
			Path:    filepath.Join("testgrid", "specs", p.Name+".yaml"),
			Content: content,
		})
	}
	for i := range m.OSes {
		o := &m.OSes[i]
		if !o.BundleDockerfile {
			continue
		}
		content, err := renderBundleDockerfile(o)
		if err != nil {
			return nil, err
		}
		out = append(out, Artifact{
			Path:    bundleDockerfilePath(o),
			Content: content,
		})
	}
	return out, nil
}

// Write renders all artifacts and writes them under root. It returns the list of
// paths that changed on disk.
func (m *Matrix) Write(root string) ([]string, error) {
	arts, err := m.Artifacts()
	if err != nil {
		return nil, err
	}
	var changed []string
	for _, a := range arts {
		full := filepath.Join(root, a.Path)
		existing, err := os.ReadFile(full)
		if err == nil && string(existing) == string(a.Content) {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			return nil, fmt.Errorf("mkdir for %s: %w", a.Path, err)
		}
		if err := os.WriteFile(full, a.Content, 0o644); err != nil {
			return nil, fmt.Errorf("write %s: %w", a.Path, err)
		}
		changed = append(changed, a.Path)
	}
	return changed, nil
}

// Check renders all artifacts and returns the list of repo-relative paths whose
// committed contents differ from what the registry would generate (i.e. stale
// generated files). An empty result means everything is in sync.
func (m *Matrix) Check(root string) ([]string, error) {
	arts, err := m.Artifacts()
	if err != nil {
		return nil, err
	}
	var stale []string
	for _, a := range arts {
		full := filepath.Join(root, a.Path)
		existing, err := os.ReadFile(full)
		if err != nil {
			stale = append(stale, a.Path)
			continue
		}
		if string(existing) != string(a.Content) {
			stale = append(stale, a.Path)
		}
	}
	return stale, nil
}
