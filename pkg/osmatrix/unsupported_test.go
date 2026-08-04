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

func TestRenderUnsupportedCapabilityDoesNotGrowUntrackedCategory(t *testing.T) {
	// Greptile flagged: "a docker-only region omits a newly-added OS that has a
	// Kubernetes minimum but no Docker restriction, so TestGrid attempts the
	// unsupported install." That omission is CORRECT, and this test locks it in.
	//
	// validate() forces every k8s-constrained OS to share ONE floor. A region
	// that tracks only docker belongs to a spec whose k8s version is >= that
	// floor (otherwise it would already carry k8s-exclusion lines for the
	// existing constrained OSes). A newly-added k8s-constrained OS therefore has
	// that same floor, so the docker-only spec still SUPPORTS it — appending it
	// would wrongly skip a combination the matrix says should run, breaking the
	// golden snapshot. The k8s-only OS must land ONLY in regions that track k8s.
	//
	// This is also the guard against "fixing" the finding by growing every
	// category unconditionally: that change fails here.
	const k8sOnlyAdd = `
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
`
	m := mustParse(t, k8sOnlyAdd)

	// Docker-only region: the new k8s-only OSes support docker, so under the
	// single-floor invariant the spec supports them — they must NOT appear.
	dockerRegion := []string{
		"  - amazon-2023 # docker is not supported on amazon 2023",
	}
	gotDocker := strings.Join(m.renderUnsupportedCapability(dockerRegion), "\n")
	for _, id := range []string{"ubuntu-2604", "ubuntu-2804"} {
		if strings.Contains(gotDocker, id) {
			t.Errorf("k8s-only OS %s wrongly grown into a docker-only region (would skip a supported combination), got:\n%s", id, gotDocker)
		}
	}
	if !strings.Contains(gotDocker, "amazon-2023") {
		t.Errorf("docker exclusion amazon-2023 must be kept, got:\n%s", gotDocker)
	}

	// A region that DOES track k8s correctly grows to include the new OS.
	k8sRegion := []string{
		"  - ubuntu-2604 # Kubernetes versions < 1.24 are not supported on Ubuntu 26.04",
	}
	gotK8s := strings.Join(m.renderUnsupportedCapability(k8sRegion), "\n")
	want2804 := "  - ubuntu-2804 # Kubernetes versions < 1.24 are not supported on Ubuntu 28.04"
	if !strings.Contains(gotK8s, want2804) {
		t.Errorf("k8s region must grow to include the new k8s-constrained OS, got:\n%s", gotK8s)
	}
	if strings.Contains(gotK8s, "amazon-2023") {
		t.Errorf("docker-only OS amazon-2023 wrongly grown into a k8s region, got:\n%s", gotK8s)
	}
}

func TestRenderUnsupportedCapabilityEmptiedRegionKeepsCategoryAndRegrows(t *testing.T) {
	// Greptile P1: when every constraint in a region is relaxed, the region body
	// shrinks to empty. Category memory was inferred only from present lines, so a
	// later matrix edit that re-adds a constraint had nothing to grow into and the
	// OS was silently omitted -> TestGrid runs an unsupported combination.
	//
	// The fix persists the tracked category as an anchor comment when a category
	// empties, so a subsequent regenerate recovers it and regrows correctly. This
	// exercises the full cross-regenerate cycle: relax -> empty (anchor) -> re-add.

	// Cycle 1: ubuntu-2404 is docker-SUPPORTED, so the docker constraint is gone.
	const relaxed = `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/noble.img
    preinit: ""
    preinitStyle: empty
pools: []
`
	m0 := mustParse(t, relaxed)
	region := []string{
		"  - ubuntu-2404 # docker is not supported on Ubuntu 24.04",
	}
	emptied := m0.renderUnsupportedCapability(region)
	joined0 := strings.Join(emptied, "\n")
	if strings.Contains(joined0, "ubuntu-2404") {
		t.Errorf("relaxed docker exclusion must be dropped, got:\n%s", joined0)
	}
	if !strings.Contains(joined0, "os-matrix-capability-anchor: docker") {
		t.Errorf("emptied docker region must keep a docker anchor so it can regrow, got:\n%s", joined0)
	}

	// Cycle 2: ubuntu-2404 is docker-UNSUPPORTED again. Feeding the anchor-only
	// body from cycle 1 must regrow the exclusion under the docker category.
	const reAdded = `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/noble.img
    preinit: ""
    preinitStyle: empty
    dockerSupported: false
pools: []
`
	m1 := mustParse(t, reAdded)
	regrown := m1.renderUnsupportedCapability(emptied)
	joined1 := strings.Join(regrown, "\n")
	want := "  - ubuntu-2404 # docker is not supported on Ubuntu 24.04"
	if !strings.Contains(joined1, want) {
		t.Errorf("re-added constraint must regrow the OS into the (previously empty) region, got:\n%s", joined1)
	}
	if strings.Contains(joined1, "os-matrix-capability-anchor") {
		t.Errorf("anchor must be dropped once the category has a real exclusion again, got:\n%s", joined1)
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
