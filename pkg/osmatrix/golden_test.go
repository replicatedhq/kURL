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

func truncate(b []byte) string {
	const maxLen = 400
	if len(b) > maxLen {
		return string(b[:maxLen]) + "...(truncated)"
	}
	return string(b)
}
