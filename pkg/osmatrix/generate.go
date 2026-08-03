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

// spliceRegion is a generated region inside a hand-maintained file. Exactly one
// of body/transform is set: body renders a single-occurrence region from the
// registry; transform rewrites every occurrence of the region from its own
// current content plus the registry.
type spliceRegion struct {
	id        string
	body      func() []string
	transform func(current []string) []string
}

// spliceFile is a hand-maintained file with one or more generated regions.
type spliceFile struct {
	path    string
	regions []spliceRegion
}

// spliceFiles lists the hand-maintained files whose OS-derived regions are
// generated in place from the registry (bucket 5: shell predicates and lists).
func (m *Matrix) spliceFiles() []spliceFile {
	common := func(f string) string { return filepath.Join("scripts", "common", f) }
	// hostPkgs is the per-test host-package install region (bucket 3), which
	// appears in many addon and shared testgrid specs.
	hostPkgs := spliceRegion{id: "ubuntu-host-packages", transform: m.renderUbuntuHostPackageCalls}
	addonTestgrid := func(addon, file string) spliceFile {
		return spliceFile{
			path:    filepath.Join("addons", addon, "template", "testgrid", file),
			regions: []spliceRegion{hostPkgs},
		}
	}
	return []spliceFile{
		{path: common("host-packages.sh"), regions: []spliceRegion{
			{id: "ubuntu-predicates", body: m.renderHostPackagesPredicates},
			{id: "host-packages-shipped", body: m.renderHostPackagesShippedGuard},
		}},
		{path: common("containerd-test.sh"), regions: []spliceRegion{
			{id: "ubuntu-predicate-stubs", body: m.renderContainerdTestPredicates},
		}},
		{path: common("preflights.sh"), regions: []spliceRegion{
			{id: "bail-supported-ubuntu", body: m.renderBailSupportedUbuntu},
		}},
		addonTestgrid("collectd", "k8s-docker.yaml"),
		addonTestgrid("containerd", "k8s-ctrd.yaml"),
		addonTestgrid("longhorn", "k8s-ctrd.yaml"),
		addonTestgrid("rook", "k8s-docker.yaml"),
		addonTestgrid("velero", "k8s-docker.yaml"),
		{path: filepath.Join("testgrid", "specs", "deploy.yaml"), regions: []spliceRegion{hostPkgs}},
		{path: filepath.Join("testgrid", "specs", "full.yaml"), regions: []spliceRegion{hostPkgs}},
	}
}

// splicedContent reads a splice file under root and returns its content with all
// generated regions refreshed from the registry. found is false when the file
// does not exist under root (used so hermetic tests on synthetic roots skip the
// real shell files; the real repo's presence is enforced by golden tests).
func (m *Matrix) splicedContent(root string, sf spliceFile) (content []byte, found bool, err error) {
	full := filepath.Join(root, sf.path)
	data, err := os.ReadFile(full)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, false, nil
		}
		return nil, false, fmt.Errorf("read %s: %w", sf.path, err)
	}
	for _, r := range sf.regions {
		if r.transform != nil {
			data, err = SpliceAllRegions(data, r.id, r.transform)
		} else {
			data, err = SpliceRegion(data, r.id, r.body())
		}
		if err != nil {
			return nil, false, fmt.Errorf("%s region %q: %w", sf.path, r.id, err)
		}
	}
	return data, true, nil
}

// Write renders all artifacts and refreshes all splice regions under root,
// returning the list of paths that changed on disk.
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
	for _, sf := range m.spliceFiles() {
		desired, found, err := m.splicedContent(root, sf)
		if err != nil {
			return nil, err
		}
		if !found {
			continue
		}
		existing, _ := os.ReadFile(filepath.Join(root, sf.path))
		if string(existing) == string(desired) {
			continue
		}
		if err := os.WriteFile(filepath.Join(root, sf.path), desired, 0o644); err != nil {
			return nil, fmt.Errorf("write %s: %w", sf.path, err)
		}
		changed = append(changed, sf.path)
	}
	return changed, nil
}

// Check returns the repo-relative paths whose committed contents differ from
// what the registry would generate (stale whole-file artifacts or drifted splice
// regions). An empty result means everything is in sync.
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
	for _, sf := range m.spliceFiles() {
		desired, found, err := m.splicedContent(root, sf)
		if err != nil {
			return nil, err
		}
		if !found {
			continue
		}
		existing, _ := os.ReadFile(filepath.Join(root, sf.path))
		if string(existing) != string(desired) {
			stale = append(stale, sf.path)
		}
	}
	return stale, nil
}
