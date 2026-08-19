package osmatrix

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
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
	// hostPkgs is the per-test host-package install region (bucket 3); cap is the
	// per-test OS-capability exclusion region (bucket 2). Both appear across many
	// addon and shared testgrid specs.
	hostPkgs := spliceRegion{id: "ubuntu-host-packages", transform: m.renderUbuntuHostPackageCalls}
	capReg := spliceRegion{id: "unsupported-capability", transform: m.renderUnsupportedCapability}
	addonTestgrid := func(addon, file string, regions ...spliceRegion) spliceFile {
		return spliceFile{
			path:    filepath.Join("addons", addon, "template", "testgrid", file),
			regions: regions,
		}
	}
	spec := func(file string, regions ...spliceRegion) spliceFile {
		return spliceFile{path: filepath.Join("testgrid", "specs", file), regions: regions}
	}
	// apparmor is the containerd apparmor guard (bucket 4), which appears twice in
	// the base install.sh and each generated per-version copy.
	apparmor := spliceRegion{id: "containerd-apparmor-guard", transform: func(_ []string) []string {
		return m.renderApparmorGuard()
	}}
	containerdInstall := func(ver string) spliceFile {
		return spliceFile{path: filepath.Join("addons", "containerd", ver, "install.sh"), regions: []spliceRegion{apparmor}}
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
		addonTestgrid("collectd", "k8s-docker.yaml", hostPkgs),
		addonTestgrid("containerd", "k8s-ctrd.yaml", hostPkgs, capReg),
		addonTestgrid("longhorn", "k8s-ctrd.yaml", hostPkgs),
		addonTestgrid("rook", "k8s-docker.yaml", hostPkgs),
		addonTestgrid("velero", "k8s-docker.yaml", hostPkgs),
		spec("deploy.yaml", hostPkgs, capReg),
		spec("full.yaml", hostPkgs, capReg),
		{path: filepath.Join("pkg", "preflight", "assets", "host-preflights.yaml"), regions: []spliceRegion{
			{id: "preflight-docker-support", body: m.renderPreflightDockerSupport},
			{id: "preflight-kubernetes-support", body: m.renderPreflightKubernetesSupport},
		}},
		containerdInstall(filepath.Join("template", "base")),
		containerdInstall("2.2.5"),
		containerdInstall("2.2.6"),
		{path: "Makefile", regions: []spliceRegion{
			{id: "makefile-ubuntu-dist-list", body: m.renderMakefileDistList},
			{id: "makefile-ubuntu-modern-targets", body: m.renderMakefileModernTargets},
		}},
		{path: filepath.Join("bin", "save-manifest-assets.sh"), regions: []spliceRegion{
			{id: "save-manifest-apt-cases", body: m.renderSaveManifestAptCases},
		}},
		{path: filepath.Join("addons", "containerd", "template", "script.sh"), regions: []spliceRegion{
			{id: "containerd-script-ubuntu-preflights", body: m.renderContainerdScriptPreflights},
			{id: "containerd-script-ubuntu-manifests", body: m.renderContainerdScriptManifests},
		}},
	}
}

// splicedContent reads a splice file under root and returns its content with all
// generated regions refreshed from the registry. found is false when the file
// does not exist under root (used so hermetic tests on synthetic roots skip the
// real shell files; the real repo's presence is enforced by golden tests).
func (m *Matrix) splicedContent(root string, sf spliceFile) (content []byte, found bool, err error) {
	full, err := safeJoin(root, sf.path)
	if err != nil {
		return nil, false, err
	}
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

// safeJoin joins a repo-relative path to root and verifies the result stays
// within root, so a generated path can never escape the repository (defense in
// depth on top of the slug validation of pool names).
func safeJoin(root, rel string) (string, error) {
	full := filepath.Join(root, rel)
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	absFull, err := filepath.Abs(full)
	if err != nil {
		return "", err
	}
	if absFull != absRoot && !strings.HasPrefix(absFull, absRoot+string(filepath.Separator)) {
		return "", fmt.Errorf("generated path %q escapes repo root", rel)
	}
	return full, nil
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
		full, err := safeJoin(root, a.Path)
		if err != nil {
			return nil, err
		}
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
		full, err := safeJoin(root, sf.path)
		if err != nil {
			return nil, err
		}
		existing, _ := os.ReadFile(full)
		if string(existing) == string(desired) {
			continue
		}
		if err := os.WriteFile(full, desired, 0o644); err != nil {
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
		full, err := safeJoin(root, a.Path)
		if err != nil {
			return nil, err
		}
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
		full, err := safeJoin(root, sf.path)
		if err != nil {
			return nil, err
		}
		existing, _ := os.ReadFile(full)
		if string(existing) != string(desired) {
			stale = append(stale, sf.path)
		}
	}
	return stale, nil
}
