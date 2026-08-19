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
