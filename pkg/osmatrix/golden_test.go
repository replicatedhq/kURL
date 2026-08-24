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

// TestGoldenCapabilityExclusions checks the real registry's capability fields
// reproduce the OS-capability exclusions that appear (repeated) in testgrid
// specs: k8s < 1.24 and no-docker both exclude exactly amazon-2023, ubuntu-2404
// and ubuntu-2604 today.
func TestGoldenCapabilityExclusions(t *testing.T) {
	m, _ := loadRealMatrix(t)
	want := map[string]bool{"amazon-2023": true, "ubuntu-2404": true, "ubuntu-2604": true}

	for _, tc := range []struct {
		name       string
		k8s        string
		usesDocker bool
	}{
		{"old-k8s", "1.19.x", false},
		{"docker", "1.32.x", true},
	} {
		got := m.CapabilityExcludedIDs(tc.k8s, tc.usesDocker)
		if len(got) != len(want) {
			t.Errorf("%s: excluded %v, want keys %v", tc.name, got, want)
			continue
		}
		for _, id := range got {
			if !want[id] {
				t.Errorf("%s: unexpected excluded id %q", tc.name, id)
			}
		}
	}

	// Current k8s without docker excludes nothing on capability grounds.
	if got := m.CapabilityExcludedIDs("1.32.x", false); len(got) != 0 {
		t.Errorf("modern k8s no-docker should exclude nothing, got %v", got)
	}
}

// TestGoldenBundleDockerfiles proves each generated Ubuntu bundle Dockerfile is
// byte-identical to the committed file, so the parametrized template is a
// zero-regression replacement for the hand-copied per-version Dockerfiles.
func TestGoldenBundleDockerfiles(t *testing.T) {
	m, root := loadRealMatrix(t)
	rendered := 0
	for i := range m.OSes {
		o := &m.OSes[i]
		if !o.BundleDockerfile {
			continue
		}
		t.Run(o.ID, func(t *testing.T) {
			got, err := renderBundleDockerfile(o)
			if err != nil {
				t.Fatalf("renderBundleDockerfile %s: %v", o.ID, err)
			}
			path := filepath.Join(root, bundleDockerfilePath(o))
			want, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("read committed Dockerfile %s: %v", path, err)
			}
			if !bytes.Equal(got, want) {
				t.Errorf("rendered %s does not match committed file", bundleDockerfilePath(o))
			}
		})
		rendered++
	}
	if rendered == 0 {
		t.Fatal("expected at least one bundleDockerfile OS in the registry")
	}
}

// TestGoldenSpliceRegionsInSync proves that regenerating every shell splice
// region from the registry reproduces the committed file exactly — i.e. the
// generated regions already match what is checked in (bucket 5). This is the
// equivalence gate for the marker-generated shell files.
func TestGoldenSpliceRegionsInSync(t *testing.T) {
	m, root := loadRealMatrix(t)
	files := m.spliceFiles()
	if len(files) == 0 {
		t.Fatal("expected splice files")
	}
	for _, sf := range files {
		t.Run(sf.path, func(t *testing.T) {
			desired, found, err := m.splicedContent(root, sf)
			if err != nil {
				t.Fatalf("splice %s: %v", sf.path, err)
			}
			if !found {
				t.Fatalf("splice file %s not found in repo", sf.path)
			}
			committed, err := os.ReadFile(filepath.Join(root, sf.path))
			if err != nil {
				t.Fatalf("read %s: %v", sf.path, err)
			}
			if !bytes.Equal(desired, committed) {
				t.Errorf("regenerated %s differs from committed (region drift)", sf.path)
			}
		})
	}
}

// TestGoldenCentOSFamilyIdentity pins the installer-identity capability fields the
// pathfinder populated for the CentOS/RHEL family and Amazon Linux 2. These make
// the registry the single source of truth for these OSes' distro/version/package
// family (previously implicit in hand-authored shell/build plumbing) and are the
// data later convoy legs build family-driven generation on. They are deliberately
// inert w.r.t. today's generated artifacts (TestGoldenSpliceRegionsInSync and
// TestGoldenPools prove byte-identity), so this test guards against silent removal.
func TestGoldenCentOSFamilyIdentity(t *testing.T) {
	m, _ := loadRealMatrix(t)
	want := map[string]struct{ distro, versionMajor, packageFamily string }{
		"amzn-20":                 {"amazonlinux", "2", "yum"},
		"centos-74":               {"centos", "7", "yum"},
		"centos-78":               {"centos", "7", "yum"},
		"centos-79":               {"centos", "7", "yum"},
		"centos-81":               {"centos", "8", "yum8"},
		"centos-82":               {"centos", "8", "yum8"},
		"centos-83":               {"centos", "8", "yum8"},
		"centos-84":               {"centos", "8", "yum8"},
		"centos-8-stream-2024-04": {"centos", "8", "yum8"},
		"centos-9":                {"centos", "9", "yum9"},
	}
	for id, w := range want {
		o, ok := m.OS(id)
		if !ok {
			t.Errorf("registry missing expected OS %q", id)
			continue
		}
		if o.Distro != w.distro || o.VersionMajor != w.versionMajor || o.PackageFamily != w.packageFamily {
			t.Errorf("%s identity = {distro:%q versionMajor:%q packageFamily:%q}, want {distro:%q versionMajor:%q packageFamily:%q}",
				id, o.Distro, o.VersionMajor, o.PackageFamily, w.distro, w.versionMajor, w.packageFamily)
		}
		// The CentOS family and Amazon Linux 2 use SELinux, not the apparmor
		// workaround, and impose no Kubernetes floor or docker exclusion today —
		// keep them out of the capability-derived preflight/exclusion regions.
		if o.ApparmorWorkaround {
			t.Errorf("%s must not set apparmorWorkaround (RHEL family uses SELinux)", id)
		}
		if o.MinKubernetes != "" {
			t.Errorf("%s must not set minKubernetes this leg (would drift preflight regions)", id)
		}
		if o.DockerSupported != nil {
			t.Errorf("%s must not set dockerSupported this leg (would drift preflight/exclusion regions)", id)
		}
	}
}

// TestGoldenOracleFamilyIdentity pins the installer-identity capability fields for
// the Oracle Linux family leg (ol-79 EL7, ol-8x EL8). Distro is "oracle" — the
// troubleshoot hostOS analyzer token used by the hand-authored Oracle preflights
// (e.g. rook's `when: "oracle < 8"`), matching how the pathfinder used
// "amazonlinux" for Amazon. Oracle 7/8 predate the rhel-9-variant family (majors
// 9/10), so they carry NO family tag; like the CentOS leg these fields are inert
// w.r.t. today's generated artifacts (TestGoldenSpliceRegionsInSync and
// TestGoldenPools prove byte-identity), so this test guards against silent removal.
func TestGoldenOracleFamilyIdentity(t *testing.T) {
	m, _ := loadRealMatrix(t)
	want := map[string]struct{ distro, versionMajor, packageFamily string }{
		"ol-79": {"oracle", "7", "yum"},
		"ol-8x": {"oracle", "8", "yum8"},
	}
	for id, w := range want {
		o, ok := m.OS(id)
		if !ok {
			t.Errorf("registry missing expected OS %q", id)
			continue
		}
		if o.Distro != w.distro || o.VersionMajor != w.versionMajor || o.PackageFamily != w.packageFamily {
			t.Errorf("%s identity = {distro:%q versionMajor:%q packageFamily:%q}, want {distro:%q versionMajor:%q packageFamily:%q}",
				id, o.Distro, o.VersionMajor, o.PackageFamily, w.distro, w.versionMajor, w.packageFamily)
		}
		// Oracle Linux 7/8 use SELinux (not the apparmor workaround), support
		// Docker, and impose no Kubernetes floor — keep them out of the
		// capability-derived preflight/exclusion regions, and out of any family
		// (rhel-9-variant matches majors 9/10 only, which EL7/EL8 are not).
		if o.ApparmorWorkaround {
			t.Errorf("%s must not set apparmorWorkaround (Oracle family uses SELinux)", id)
		}
		if o.MinKubernetes != "" {
			t.Errorf("%s must not set minKubernetes this leg (would drift preflight regions)", id)
		}
		if o.DockerSupported != nil {
			t.Errorf("%s must not set dockerSupported this leg (would drift preflight/exclusion regions)", id)
		}
		if o.Family != "" {
			t.Errorf("%s must not set family (rhel-9-variant matches majors 9/10, not EL7/EL8)", id)
		}
	}
}

// TestGoldenUbuntuLegacyIdentity pins the capability modeling of the legacy Ubuntu
// releases (18.04/20.04/22.04). Unlike the newer 24.04/26.04 — which kURL special-
// cases (native containerd, the apparmor workaround, no Docker, a 1.24 Kubernetes
// floor) — legacy Ubuntu is the *default* apt path: Docker is supported, there is no
// Kubernetes floor, and kURL ships bundled host packages for it via the generic dpkg
// path (bundles/k8s-ubuntu1804/2004/2204). So the only registry identity these rows
// need is distro + versionMajor; the remaining capability fields are deliberately
// ABSENT and this test locks that in.
//
// For Ubuntu these absences are behavior-critical, not merely inert: each field is
// consumed generatively (see shell.go). Setting them here would silently change
// committed artifacts and installer behavior —
//   - packageFamily apt* => phantom save-manifest apt<NN> cases + containerd manifest
//     entries (legacy Ubuntu's apt plumbing is the hand-authored bare `apt)` fan-out
//     in bin/save-manifest-assets.sh, outside the generated markers per the os-matrix
//     scope note), so it must stay empty;
//   - hostPackagesShipped => an is_ubuntu_<NN>04 predicate + a host_packages_shipped
//     negated clause claiming a native path, which is the OPPOSITE of reality (kURL
//     bundles them);
//   - apparmorWorkaround => a wrong is_ubuntu_<NN>04 arm in the containerd apparmor
//     guard;
//   - dockerSupported=false / minKubernetes => wrong Docker/Kubernetes preflight fail
//     outcomes and testgrid capability exclusions (see TestGoldenCapabilityExclusions,
//     which pins today's exclusion set to exactly amazon-2023/ubuntu-2404/ubuntu-2604).
func TestGoldenUbuntuLegacyIdentity(t *testing.T) {
	m, _ := loadRealMatrix(t)
	want := map[string]struct{ distro, versionMajor string }{
		"ubuntu-1804": {"ubuntu", "18"},
		"ubuntu-2004": {"ubuntu", "20"},
		"ubuntu-2204": {"ubuntu", "22"},
	}
	for id, w := range want {
		o, ok := m.OS(id)
		if !ok {
			t.Errorf("registry missing expected OS %q", id)
			continue
		}
		if o.Distro != w.distro || o.VersionMajor != w.versionMajor {
			t.Errorf("%s identity = {distro:%q versionMajor:%q}, want {distro:%q versionMajor:%q}",
				id, o.Distro, o.VersionMajor, w.distro, w.versionMajor)
		}
		// Deliberately-absent capability fields — each is consumed generatively for
		// distro==ubuntu, so a non-zero value here would drift committed artifacts.
		if o.PackageFamily != "" {
			t.Errorf("%s must not set packageFamily (no apt<NN> family; legacy Ubuntu uses the hand-authored bare `apt` path, so a value would emit phantom save-manifest/containerd cases)", id)
		}
		if o.HostPackagesShipped {
			t.Errorf("%s must not set hostPackagesShipped (kURL ships bundled host packages for it via the generic dpkg path; setting it would render a spurious is_ubuntu_%s04 predicate + guard clause)", id, o.VersionMajor)
		}
		if o.ApparmorWorkaround {
			t.Errorf("%s must not set apparmorWorkaround (only 24.04+ needs it; setting it would add a wrong arm to the containerd apparmor guard)", id)
		}
		if o.MinKubernetes != "" {
			t.Errorf("%s must not set minKubernetes (legacy Ubuntu has no Kubernetes floor; setting it would drift the Kubernetes-support preflight + exclusions)", id)
		}
		if o.DockerSupported != nil {
			t.Errorf("%s must not set dockerSupported (Docker is supported on legacy Ubuntu; setting false would drift the Docker-support preflight + exclusions)", id)
		}
		if o.Family != "" {
			t.Errorf("%s must not set a family (no legacy-Ubuntu family predicate exists)", id)
		}
	}
}

// TestGoldenFamilyModel pins the shared distro-family model the pathfinder
// established: the two families the RHEL/Amazon predicates render from, and the
// member OSes tagged into them from the CentOS/Amazon driving data. The predicate
// bodies' byte-identity is proven by TestGoldenSpliceRegionsInSync (the
// family-predicates region of host-packages.sh); this test guards the registry
// data those predicates derive from, and documents the extension point later legs
// use (tagging their OSes with `family: rhel-9-variant` etc.).
func TestGoldenFamilyModel(t *testing.T) {
	m, _ := loadRealMatrix(t)

	wantFamilies := map[string]struct {
		predicate           string
		lsbDist             []string
		versionMajors       []string
		hostPackagesShipped bool
	}{
		"rhel-9-variant": {"is_rhel_9_variant", []string{"centos", "rhel", "ol", "rocky"}, []string{"9", "10"}, true},
		"amazon-2023":    {"is_amazon_2023", []string{"amzn"}, []string{"2023"}, true},
	}
	if len(m.Families) != len(wantFamilies) {
		t.Errorf("registry has %d families, want %d", len(m.Families), len(wantFamilies))
	}
	for i := range m.Families {
		f := &m.Families[i]
		w, ok := wantFamilies[f.Name]
		if !ok {
			t.Errorf("unexpected family %q", f.Name)
			continue
		}
		if f.Predicate != w.predicate || !equalStrings(f.LSBDist, w.lsbDist) ||
			!equalStrings(f.VersionMajors, w.versionMajors) || f.HostPackagesShipped != w.hostPackagesShipped {
			t.Errorf("family %q = {predicate:%q lsbDist:%v versionMajors:%v hostPackagesShipped:%v}, want {%q %v %v %v}",
				f.Name, f.Predicate, f.LSBDist, f.VersionMajors, f.HostPackagesShipped,
				w.predicate, w.lsbDist, w.versionMajors, w.hostPackagesShipped)
		}
	}

	// The CentOS/Amazon driving data tags at least one member into each family.
	wantTags := map[string]string{"centos-9": "rhel-9-variant", "amazon-2023": "amazon-2023"}
	for id, family := range wantTags {
		o, ok := m.OS(id)
		if !ok {
			t.Errorf("registry missing %q", id)
			continue
		}
		if o.Family != family {
			t.Errorf("%s family = %q, want %q", id, o.Family, family)
		}
	}
}

// TestGoldenRockyFamily pins the Rocky Linux capability data tagged onto the
// pathfinder's rhel-9-variant model. Rocky ships no dedicated testgrid family
// predicate of its own — it joins is_rhel_9_variant (whose lsbDist already lists
// "rocky") via each OS's `family:` tag — so this test guards the per-OS identity
// data (distro/versionMajor/packageFamily) and the family membership the runtime
// predicate relies on. Rocky needs no dockerSupported/minKubernetes/apparmor
// constraint: is_docker_version_supported treats rocky as Docker-capable at every
// major, and host-package shipping is handled at the rhel-9-variant family level.
func TestGoldenRockyFamily(t *testing.T) {
	m, _ := loadRealMatrix(t)

	want := map[string]struct {
		distro, versionMajor, packageFamily, family string
	}{
		"rocky-9":          {"rocky", "9", "yum9", "rhel-9-variant"},
		"rocky-9-customer": {"rocky", "9", "yum9", "rhel-9-variant"},
		"rocky-91":         {"rocky", "9", "yum9", "rhel-9-variant"},
		"rocky-98":         {"rocky", "9", "yum9", "rhel-9-variant"},
		"rocky-10":         {"rocky", "10", "yum10", "rhel-9-variant"},
	}
	for key, w := range want {
		o, ok := m.OS(key)
		if !ok {
			t.Errorf("registry missing %q", key)
			continue
		}
		if o.Distro != w.distro || o.VersionMajor != w.versionMajor ||
			o.PackageFamily != w.packageFamily || o.Family != w.family {
			t.Errorf("%s = {distro:%q versionMajor:%q packageFamily:%q family:%q}, want {%q %q %q %q}",
				key, o.Distro, o.VersionMajor, o.PackageFamily, o.Family,
				w.distro, w.versionMajor, w.packageFamily, w.family)
		}
		// Rocky inherits Docker support and the k8s floor from the shared model;
		// it must not carry its own capability constraints.
		if o.MinKubernetes != "" || o.DockerSupported != nil || o.ApparmorWorkaround || o.HostPackagesShipped {
			t.Errorf("%s carries unexpected capability constraint(s): minKubernetes=%q dockerSupported=%v apparmor=%v hostPackagesShipped=%v",
				key, o.MinKubernetes, o.DockerSupported, o.ApparmorWorkaround, o.HostPackagesShipped)
		}
	}
}

func truncate(b []byte) string {
	const maxLen = 400
	if len(b) > maxLen {
		return string(b[:maxLen]) + "...(truncated)"
	}
	return string(b)
}
