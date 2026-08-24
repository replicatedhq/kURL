package osmatrix

import (
	"strings"
	"testing"
)

// familyFixture declares the two shipped-elsewhere distro families (multi-distro
// RHEL-9-variant and single-distro Amazon-2023) plus a member OS of each, to drive
// both the predicate renderer and the family-tag validation.
const familyFixture = `
families:
  - name: rhel-9-variant
    predicate: is_rhel_9_variant
    description: RHEL 9 (or 10) or a derivative
    lsbDist: [centos, rhel, ol, rocky]
    versionMajors: ["9", "10"]
    hostPackagesShipped: true
  - name: amazon-2023
    predicate: is_amazon_2023
    description: Amazon 2023.
    lsbDist: [amzn]
    versionMajors: ["2023"]
    hostPackagesShipped: true
oses:
  - id: centos-9
    name: CentOS 9
    version: "stream"
    vmimageuri: https://example.com/c9.qcow2
    preinit: ""
    preinitStyle: empty
    distro: centos
    versionMajor: "9"
    packageFamily: yum9
    family: rhel-9-variant
  - id: amazon-2023
    name: Amazon Linux
    version: "2023"
    vmimageuri: https://example.com/al2023.img
    preinit: ""
    preinitStyle: empty
    distro: amazonlinux
    versionMajor: "2023"
    family: amazon-2023
pools: []
`

func TestRenderFamilyPredicates(t *testing.T) {
	m := mustParse(t, familyFixture)
	got := strings.Join(m.renderFamilyPredicates(), "\n")
	want := strings.Join([]string{
		"# is_rhel_9_variant returns 0 if the current distro is RHEL 9 (or 10) or a derivative",
		"function is_rhel_9_variant() {",
		`    if [ "$DIST_VERSION_MAJOR" != "9" ] && [ "$DIST_VERSION_MAJOR" != "10" ]; then`,
		"        return 1",
		"    fi",
		"",
		`    case "$LSB_DIST" in`,
		"        centos|rhel|ol|rocky)",
		"            return 0",
		"            ;;",
		"        *)",
		"            return 1",
		"            ;;",
		"    esac",
		"}",
		"",
		"# is_amazon_2023 returns 0 if the current distro is Amazon 2023.",
		"function is_amazon_2023() {",
		`    if [ "$DIST_VERSION_MAJOR" != "2023" ]; then`,
		"        return 1",
		"    fi",
		`    if [ "$LSB_DIST" != "amzn" ]; then`,
		"        return 1",
		"    fi",
		"    return 0",
		"}",
	}, "\n")
	if got != want {
		t.Errorf("renderFamilyPredicates mismatch:\n got:\n%s\n\nwant:\n%s", got, want)
	}
}

// oneFamily wraps a single families: entry (indented two spaces) with the minimal
// surrounding document (a matching member OS and empty pools) so a crafted family
// field can be fed through Parse. The member OS carries no family tag, so only the
// family entry itself is under test.
func oneFamily(entry string) string {
	return "families:\n" + entry + `
oses:
  - id: placeholder
    name: Placeholder
    version: "1"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
pools: []
`
}

// TestValidateRejectsBadFamily feeds crafted-bad values through every family
// injection-boundary validator (predicate/description/lsbDist/versionMajor) plus
// the two structural family invariants added as review hardening: a family
// predicate may not duplicate another and may not squat the reserved is_ubuntu_
// prefix (which the per-version Ubuntu predicates own). Every case must fail Parse.
func TestValidateRejectsBadFamily(t *testing.T) {
	cases := []struct {
		name, entry, wantSubstr string
	}{
		{"predicate shell injection", `  - name: bad
    predicate: "is_x; rm -rf /"
    description: Bad
    lsbDist: [centos]
    versionMajors: ["9"]`, "predicate"},
		{"description quote", `  - name: bad
    predicate: is_bad
    description: "he said \"hi\""
    lsbDist: [centos]
    versionMajors: ["9"]`, "description"},
		{"description newline", `  - name: bad
    predicate: is_bad
    description: "line1\ninjected: key"
    lsbDist: [centos]
    versionMajors: ["9"]`, "description"},
		{"lsbDist space", `  - name: bad
    predicate: is_bad
    description: Bad
    lsbDist: ["a b"]
    versionMajors: ["9"]`, "lsbDist"},
		{"versionMajor non-digit", `  - name: bad
    predicate: is_bad
    description: Bad
    lsbDist: [centos]
    versionMajors: ["9x"]`, "versionMajor"},
		{"empty lsbDist", `  - name: bad
    predicate: is_bad
    description: Bad
    lsbDist: []
    versionMajors: ["9"]`, "lsbDist"},
		{"empty versionMajors", `  - name: bad
    predicate: is_bad
    description: Bad
    lsbDist: [centos]
    versionMajors: []`, "versionMajors"},
		{"predicate reserves is_ubuntu_", `  - name: bad
    predicate: is_ubuntu_2404
    description: Bad
    lsbDist: [ubuntu]
    versionMajors: ["24"]`, "is_ubuntu_"},
	}
	for _, c := range cases {
		_, err := Parse([]byte(oneFamily(c.entry)))
		if err == nil {
			t.Errorf("%s: expected validation error, got nil", c.name)
			continue
		}
		if !strings.Contains(err.Error(), c.wantSubstr) {
			t.Errorf("%s: error %q does not mention %q", c.name, err, c.wantSubstr)
		}
	}
}

// TestValidateRejectsDuplicateFamilyPredicate covers the review-hardening invariant
// that two families may not share a predicate: dedup is on Name only in index(), so
// distinct-named families with the same predicate would emit duplicate shell
// function defs that silently shadow.
func TestValidateRejectsDuplicateFamilyPredicate(t *testing.T) {
	_, err := Parse([]byte(`
families:
  - name: fam-a
    predicate: is_dup
    description: A
    lsbDist: [centos]
    versionMajors: ["9"]
  - name: fam-b
    predicate: is_dup
    description: B
    lsbDist: [rhel]
    versionMajors: ["9"]
oses:
  - id: placeholder
    name: Placeholder
    version: "1"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
pools: []
`))
	if err == nil || !strings.Contains(err.Error(), "duplicate family predicate") {
		t.Fatalf("expected duplicate-predicate error, got %v", err)
	}
}

// TestIndexRejectsBadFamily covers the two index() branches that had no negative
// test: an empty family name and a duplicate family name both fail at Parse.
func TestIndexRejectsBadFamily(t *testing.T) {
	_, err := Parse([]byte(`
families:
  - name: ""
    predicate: is_bad
    description: Bad
    lsbDist: [centos]
    versionMajors: ["9"]
oses: []
pools: []
`))
	if err == nil || !strings.Contains(err.Error(), "empty name") {
		t.Fatalf("expected empty-family-name error, got %v", err)
	}

	_, err = Parse([]byte(`
families:
  - name: dup
    predicate: is_a
    description: A
    lsbDist: [centos]
    versionMajors: ["9"]
  - name: dup
    predicate: is_b
    description: B
    lsbDist: [rhel]
    versionMajors: ["9"]
oses: []
pools: []
`))
	if err == nil || !strings.Contains(err.Error(), "duplicate family name") {
		t.Fatalf("expected duplicate-family-name error, got %v", err)
	}
}

func TestFamilyValidation(t *testing.T) {
	// An OS tagged with an unknown family fails at Parse.
	_, err := Parse([]byte(`
families:
  - name: rhel-9-variant
    predicate: is_rhel_9_variant
    description: RHEL 9 (or 10) or a derivative
    lsbDist: [centos, rhel, ol, rocky]
    versionMajors: ["9", "10"]
    hostPackagesShipped: true
oses:
  - id: centos-9
    name: CentOS 9
    version: "stream"
    vmimageuri: https://example.com/c9.qcow2
    preinit: ""
    preinitStyle: empty
    distro: centos
    versionMajor: "9"
    family: nope
pools: []
`))
	if err == nil {
		t.Error("expected error for OS referencing unknown family")
	}

	// A member's versionMajor outside the family's declared majors fails.
	_, err = Parse([]byte(`
families:
  - name: rhel-9-variant
    predicate: is_rhel_9_variant
    description: RHEL 9 (or 10) or a derivative
    lsbDist: [centos, rhel, ol, rocky]
    versionMajors: ["9", "10"]
    hostPackagesShipped: true
oses:
  - id: centos-7
    name: CentOS
    version: "7.9"
    vmimageuri: https://example.com/c7.qcow2
    preinit: ""
    preinitStyle: empty
    distro: centos
    versionMajor: "7"
    family: rhel-9-variant
pools: []
`))
	if err == nil {
		t.Error("expected error for family member with out-of-range versionMajor")
	}
}
