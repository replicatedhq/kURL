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
