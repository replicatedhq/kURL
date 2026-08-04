package osmatrix

import (
	"strings"
	"testing"
)

// capMatrix has the three currently-constrained OSes plus a fourth "new" OS to
// exercise the add-an-OS behavior.
const capMatrix = `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/a.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
    dockerSupported: false
  - id: ubuntu-2604
    name: Ubuntu
    version: "26.04"
    vmimageuri: https://example.com/b.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
    dockerSupported: false
  - id: amazon-2023
    name: Amazon Linux
    version: "2023"
    vmimageuri: https://example.com/c.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
    dockerSupported: false
  - id: ubuntu-2804
    name: Ubuntu
    version: "28.04"
    vmimageuri: https://example.com/d.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
    dockerSupported: false
pools: []
`

func TestWrapCapabilityRunsFullVsSubset(t *testing.T) {
	// m3's constrained set is exactly the three OSes below, so the run is "full".
	m3 := mustParse(t, capFixture) // ubuntu-2404, ubuntu-2604, amazon-2023
	got := string(m3.wrapCapabilityRuns([]byte(
		"  unsupportedOSIDs:\n" +
			"  - rocky-9 # docker is not supported on rhel 9 variants\n" +
			"  - amazon-2023 # docker is not supported on amazon 2023\n" +
			"  - ubuntu-2404 # docker is not supported on Ubuntu 24.04\n" +
			"  - ubuntu-2604 # docker is not supported on Ubuntu 26.04\n")))
	if !strings.Contains(got, "BEGIN GENERATED os-matrix: unsupported-capability") {
		t.Error("expected full docker run to be wrapped")
	}
	// rocky-9 (not a capability OS) stays outside the markers.
	beginIdx := strings.Index(got, "BEGIN GENERATED")
	if strings.Index(got, "rocky-9") > beginIdx {
		t.Error("rocky-9 should remain before the generated region")
	}

	// A SUBSET run (only amazon-2023) is NOT wrapped.
	subset := "  unsupportedOSIDs:\n" +
		"  - amazon-2023 # docker is not supported on amazon 2023\n" +
		"  - ubuntu-2204 # some spec reason\n"
	if gotSub := string(m3.wrapCapabilityRuns([]byte(subset))); strings.Contains(gotSub, "BEGIN GENERATED") {
		t.Errorf("subset run must not be wrapped:\n%s", gotSub)
	}
}

func TestRenderUnsupportedCapabilityAddsNewOS(t *testing.T) {
	m := mustParse(t, capMatrix) // constrained set includes ubuntu-2804

	// A region complete for the pre-2804 world gains ubuntu-2804 on regenerate.
	region := []string{
		"  - amazon-2023 # docker is not supported on amazon 2023",
		"  - ubuntu-2404 # docker is not supported on Ubuntu 24.04",
		"  - ubuntu-2604 # docker is not supported on Ubuntu 26.04",
	}
	got := m.renderUnsupportedCapability(region)
	joined := strings.Join(got, "\n")
	// Existing lines preserved verbatim (typo-free here) and 2804 appended.
	for _, l := range region {
		if !strings.Contains(joined, l) {
			t.Errorf("existing line dropped: %q", l)
		}
	}
	want2804 := "  - ubuntu-2804 # docker is not supported on Ubuntu 28.04"
	if !strings.Contains(joined, want2804) {
		t.Errorf("expected appended %q, got:\n%s", want2804, joined)
	}
}

func TestRenderUnsupportedCapabilityPreservesTypos(t *testing.T) {
	m := mustParse(t, capFixture) // no new OS; nothing to append
	region := []string{
		"  - amazon-2023 # docker is not supported on amazon 2023",
		"  - ubuntu-2404 # docker is not supported on amazon 2023", // real typo from main
		"  - ubuntu-2604 # docker is not supported on ubuntu 2604",
	}
	got := strings.Join(m.renderUnsupportedCapability(region), "\n")
	if got != strings.Join(region, "\n") {
		t.Errorf("expected verbatim preservation (no new OS), got:\n%s", got)
	}
}

func TestRenderUnsupportedCapabilityShrinksWhenOSRemoved(t *testing.T) {
	// capFixture's docker-unsupported set is exactly amazon-2023, ubuntu-2404,
	// ubuntu-2604. A region that still lists a since-removed OS must drop it so
	// TestGrid stops skipping combinations the current matrix says should run.
	m := mustParse(t, capFixture)
	region := []string{
		"  - amazon-2023 # docker is not supported on amazon 2023",
		"  - ubuntu-2404 # docker is not supported on Ubuntu 24.04",
		"  - ubuntu-2604 # docker is not supported on Ubuntu 26.04",
		"  - ubuntu-2804 # docker is not supported on Ubuntu 28.04", // OS removed from registry
	}
	got := strings.Join(m.renderUnsupportedCapability(region), "\n")
	if strings.Contains(got, "ubuntu-2804") {
		t.Errorf("stale exclusion ubuntu-2804 should be dropped, got:\n%s", got)
	}
	for _, id := range []string{"amazon-2023", "ubuntu-2404", "ubuntu-2604"} {
		if !strings.Contains(got, id) {
			t.Errorf("still-justified exclusion %s must be kept, got:\n%s", id, got)
		}
	}
}

func TestRenderUnsupportedCapabilityShrinksWhenConstraintRelaxed(t *testing.T) {
	// ubuntu-2404 keeps dockerSupported:false (still a docker-capability OS) but
	// has NO minKubernetes — so its k8s exclusion is no longer justified and must
	// be dropped, even though the OS remains constrained for docker. This proves
	// the shrink decision is per-category, not "is this OS constrained at all".
	const relaxed = `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/noble.img
    preinit: ""
    preinitStyle: empty
    dockerSupported: false
  - id: ubuntu-2604
    name: Ubuntu
    version: "26.04"
    vmimageuri: https://example.com/resolute.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
    dockerSupported: false
pools: []
`
	m := mustParse(t, relaxed)
	region := []string{
		"  - ubuntu-2404 # Kubernetes versions < 1.24 are not supported on Ubuntu 24.04",
		"  - ubuntu-2604 # Kubernetes versions < 1.24 are not supported on Ubuntu 26.04",
	}
	got := strings.Join(m.renderUnsupportedCapability(region), "\n")
	if strings.Contains(got, "ubuntu-2404") {
		t.Errorf("relaxed k8s exclusion ubuntu-2404 should be dropped, got:\n%s", got)
	}
	if !strings.Contains(got, "ubuntu-2604") {
		t.Errorf("still-justified k8s exclusion ubuntu-2604 must be kept, got:\n%s", got)
	}
}

func TestRenderUnsupportedCapabilityGrowsNonPrimaryCategory(t *testing.T) {
	// A MIXED region: amazon-2023 is excluded for docker (the PRIMARY category,
	// first line) and ubuntu-2604 for a Kubernetes floor. A newly-constrained
	// k8s-only OS (ubuntu-2804) must be appended under its OWN (non-primary)
	// category — the growth side is per-category, symmetric with shrink.
	const mixedGrow = `
oses:
  - id: amazon-2023
    name: Amazon Linux
    version: "2023"
    vmimageuri: https://example.com/al2023.img
    preinit: ""
    preinitStyle: empty
    dockerSupported: false
  - id: ubuntu-2604
    name: Ubuntu
    version: "26.04"
    vmimageuri: https://example.com/resolute.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
  - id: ubuntu-2804
    name: Ubuntu
    version: "28.04"
    vmimageuri: https://example.com/oracular.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
pools: []
`
	m := mustParse(t, mixedGrow)
	region := []string{
		"  - amazon-2023 # docker is not supported on amazon 2023",
		"  - ubuntu-2604 # Kubernetes versions < 1.24 are not supported on Ubuntu 26.04",
	}
	got := strings.Join(m.renderUnsupportedCapability(region), "\n")
	want2804 := "  - ubuntu-2804 # Kubernetes versions < 1.24 are not supported on Ubuntu 28.04"
	if !strings.Contains(got, want2804) {
		t.Errorf("newly-constrained non-primary (k8s) OS must be appended under its own category, got:\n%s", got)
	}
	// amazon-2023 is docker-only; it must not be re-appended under k8s.
	if strings.Contains(got, "amazon-2023 # Kubernetes") {
		t.Errorf("docker-only OS wrongly appended under k8s, got:\n%s", got)
	}
}

func TestCapabilityCategory(t *testing.T) {
	cases := map[string]string{
		"# Kubernetes versions < 1.24 are not supported on Ubuntu 24.04.": "k8s",
		"# docker is not supported on amazon 2023":                        "docker",
		"# Docker is not supported on Ubuntu 24.04":                       "docker",
		"# containerd 1.4.x is not available on ubuntu 22.04":             "",
	}
	for comment, want := range cases {
		if got := capabilityCategory(comment); got != want {
			t.Errorf("capabilityCategory(%q) = %q, want %q", comment, got, want)
		}
	}
}
