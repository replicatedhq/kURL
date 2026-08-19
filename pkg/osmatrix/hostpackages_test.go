package osmatrix

import (
	"strings"
	"testing"
)

const hostPkgFixture = `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/noble.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "24"
    hostPackagesShipped: true
  - id: ubuntu-2604
    name: Ubuntu
    version: "26.04"
    vmimageuri: https://example.com/resolute.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "26"
    hostPackagesShipped: true
  - id: ubuntu-2204
    name: Ubuntu
    version: "22.04"
    vmimageuri: https://example.com/jammy.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    versionMajor: "22"
pools: []
`

func TestRenderUbuntuHostPackageCalls(t *testing.T) {
	m := mustParse(t, hostPkgFixture)

	// Preserves indentation and package list, one line per shipped Ubuntu.
	got := m.renderUbuntuHostPackageCalls([]string{"    ubuntu_2404_install_host_packages lvm2 nfs-common"})
	want := []string{
		"    ubuntu_2404_install_host_packages lvm2 nfs-common",
		"    ubuntu_2604_install_host_packages lvm2 nfs-common",
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Errorf("got %q want %q", got, want)
	}

	// ubuntu-2204 (no hostPackagesShipped) must NOT get a call.
	for _, l := range got {
		if strings.Contains(l, "ubuntu_2204") {
			t.Errorf("unexpected ubuntu-2204 call: %q", got)
		}
	}

	// No recognizable call => returned unchanged.
	unchanged := []string{"# just a comment"}
	if out := m.renderUbuntuHostPackageCalls(unchanged); strings.Join(out, "\n") != strings.Join(unchanged, "\n") {
		t.Errorf("expected unchanged, got %q", out)
	}
}

func TestSpliceAllRegions(t *testing.T) {
	file := strings.Join([]string{
		"a: 1",
		"    # BEGIN GENERATED os-matrix: hp",
		"    ubuntu_2404_install_host_packages lvm2",
		"    # END GENERATED os-matrix: hp",
		"b: 2",
		"    # BEGIN GENERATED os-matrix: hp",
		"    ubuntu_2404_install_host_packages nfs-common",
		"    ubuntu_2604_install_host_packages nfs-common",
		"    # END GENERATED os-matrix: hp",
		"c: 3",
	}, "\n") + "\n"

	m := mustParse(t, hostPkgFixture)
	got, err := SpliceAllRegions([]byte(file), "hp", m.renderUbuntuHostPackageCalls)
	if err != nil {
		t.Fatalf("SpliceAllRegions: %v", err)
	}
	// First region gains a 2604 line; second is already complete; content
	// outside markers is untouched.
	want := strings.Join([]string{
		"a: 1",
		"    # BEGIN GENERATED os-matrix: hp",
		"    ubuntu_2404_install_host_packages lvm2",
		"    ubuntu_2604_install_host_packages lvm2",
		"    # END GENERATED os-matrix: hp",
		"b: 2",
		"    # BEGIN GENERATED os-matrix: hp",
		"    ubuntu_2404_install_host_packages nfs-common",
		"    ubuntu_2604_install_host_packages nfs-common",
		"    # END GENERATED os-matrix: hp",
		"c: 3",
	}, "\n") + "\n"
	if string(got) != want {
		t.Errorf("SpliceAllRegions mismatch:\n got %q\nwant %q", got, want)
	}
}

func TestSpliceAllRegionsUnterminated(t *testing.T) {
	bad := "# BEGIN GENERATED os-matrix: hp\nfoo\n"
	if _, err := SpliceAllRegions([]byte(bad), "hp", func(c []string) []string { return c }); err == nil {
		t.Error("expected error for unterminated region")
	}
}
