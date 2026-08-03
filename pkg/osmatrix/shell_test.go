package osmatrix

import (
	"strings"
	"testing"
)

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
