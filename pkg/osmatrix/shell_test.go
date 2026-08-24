package osmatrix

import (
	"strings"
	"testing"
)

func TestRenderHostPackagesShippedGuard(t *testing.T) {
	// The guard is composed of two parts: the hand-authored RHEL/Amazon FAMILY
	// predicates (a fixed, documented list) followed by the data-driven per-version
	// apt (Ubuntu) predicates, one per host-package-shipping Ubuntu release, in
	// registry order. Adding a shipping Ubuntu release must extend the guard.
	const familyBlock = `
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
`
	m := mustParse(t, familyBlock+`
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "24"
    hostPackagesShipped: true
  - id: ubuntu-2604
    name: Ubuntu
    version: "26.04"
    vmimageuri: https://e/y.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "26"
    hostPackagesShipped: true
  - id: ubuntu-2204
    name: Ubuntu
    version: "22.04"
    vmimageuri: https://e/z.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "22"
pools: []
`)
	got := strings.Join(m.renderHostPackagesShippedGuard(), "\n")
	want := "    if ! is_rhel_9_variant && ! is_amazon_2023 && ! is_ubuntu_2404 && ! is_ubuntu_2604; then"
	if got != want {
		t.Errorf("host_packages_shipped guard = %q, want %q", got, want)
	}

	// The family predicates are present even when NO Ubuntu ships host packages,
	// so a family-only registry still renders a valid guard.
	m2 := mustParse(t, familyBlock+`
oses:
  - id: ubuntu-2204
    name: Ubuntu
    version: "22.04"
    vmimageuri: https://e/z.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "22"
pools: []
`)
	got2 := strings.Join(m2.renderHostPackagesShippedGuard(), "\n")
	want2 := "    if ! is_rhel_9_variant && ! is_amazon_2023; then"
	if got2 != want2 {
		t.Errorf("family-only guard = %q, want %q", got2, want2)
	}
}

// TestRenderHostPackagesShippedGuardEmpty covers the degenerate edge (review
// hardening): a registry with zero shipping families AND zero shipping Ubuntus must
// not emit the malformed `if ; then`. With nothing excluded from generic detection,
// the guard is vacuously true, so it renders `if true; then`.
func TestRenderHostPackagesShippedGuardEmpty(t *testing.T) {
	m := mustParse(t, `
oses:
  - id: ubuntu-2204
    name: Ubuntu
    version: "22.04"
    vmimageuri: https://e/z.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "22"
pools: []
`)
	got := strings.Join(m.renderHostPackagesShippedGuard(), "\n")
	want := "    if true; then"
	if got != want {
		t.Errorf("empty guard = %q, want %q", got, want)
	}
}

func TestRenderApparmorGuard(t *testing.T) {
	m := mustParse(t, `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "24"
    apparmorWorkaround: true
  - id: ubuntu-2604
    name: Ubuntu
    version: "26.04"
    vmimageuri: https://e/y.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "26"
    apparmorWorkaround: true
  - id: ubuntu-2204
    name: Ubuntu
    version: "22.04"
    vmimageuri: https://e/z.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "22"
pools: []
`)
	got := strings.Join(m.renderApparmorGuard(), "\n")
	want := "    if is_ubuntu_2404 || is_ubuntu_2604; then"
	if got != want {
		t.Errorf("apparmor guard = %q, want %q", got, want)
	}
}
