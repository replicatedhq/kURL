package osmatrix

import (
	"testing"
)

const testFixture = `
oses:
  - id: ubuntu-2404
    distro: ubuntu
    name: Ubuntu
    version: "24.04"
    versionMajor: "24"
    packageFamily: apt24
    vmimageuri: https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
    preinit: "apt-get update && apt-get install -y socat"
    preinitStyle: quoted
    minKubernetes: "1.24"
    dockerSupported: false
    apparmorWorkaround: true
    hostPackagesShipped: true
  - id: rocky-9
    distro: rocky
    name: Rocky Linux
    version: "9.8"
    vmimageuri: https://example.com/rocky9.qcow2
    preinit: "yum install -y nfs-utils"
    preinitStyle: block
  - id: ubuntu-1804
    distro: ubuntu
    name: Ubuntu
    version: "18.04"
    vmimageuri: https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img
    preinit: ""
    preinitStyle: empty
pools:
  - name: os-latest
    trailingNewline: false
    ids: [ubuntu-1804, ubuntu-2404]
  - name: os-min
    trailingNewline: true
    ids: [ubuntu-2404]
`

func TestParse(t *testing.T) {
	m, err := Parse([]byte(testFixture))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	if got := len(m.OSes); got != 3 {
		t.Fatalf("expected 3 oses, got %d", got)
	}

	u2404, ok := m.OS("ubuntu-2404")
	if !ok {
		t.Fatal("ubuntu-2404 not found via OS()")
	}
	if u2404.Name != "Ubuntu" || u2404.Version != "24.04" || u2404.VersionMajor != "24" {
		t.Errorf("ubuntu-2404 fields wrong: %+v", u2404)
	}
	if u2404.PackageFamily != "apt24" {
		t.Errorf("expected packageFamily apt24, got %q", u2404.PackageFamily)
	}
	if u2404.DockerSupported == nil || *u2404.DockerSupported {
		t.Errorf("expected dockerSupported=false, got %v", u2404.DockerSupported)
	}
	if !u2404.ApparmorWorkaround || !u2404.HostPackagesShipped {
		t.Errorf("expected apparmor+hostpkg true: %+v", u2404)
	}
	if u2404.MinKubernetes != "1.24" {
		t.Errorf("expected minKubernetes 1.24, got %q", u2404.MinKubernetes)
	}

	if _, ok := m.OS("does-not-exist"); ok {
		t.Error("OS() returned ok for missing id")
	}

	// Pools preserve declaration order and per-pool ids.
	if len(m.Pools) != 2 {
		t.Fatalf("expected 2 pools, got %d", len(m.Pools))
	}
	if m.Pools[0].Name != "os-latest" || m.Pools[1].Name != "os-min" {
		t.Errorf("pool order not preserved: %+v", m.Pools)
	}
	if m.Pools[0].TrailingNewline {
		t.Error("os-latest should have trailingNewline=false")
	}
	if !m.Pools[1].TrailingNewline {
		t.Error("os-min should have trailingNewline=true")
	}
}

func TestParseRejectsUnknownPoolID(t *testing.T) {
	bad := `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/x.img
    preinit: ""
    preinitStyle: empty
pools:
  - name: os-latest
    ids: [ubuntu-9999]
`
	if _, err := Parse([]byte(bad)); err == nil {
		t.Fatal("expected error for pool referencing unknown OS id, got nil")
	}
}

func TestParseRejectsDuplicateID(t *testing.T) {
	bad := `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/x.img
    preinit: ""
    preinitStyle: empty
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/y.img
    preinit: ""
    preinitStyle: empty
`
	if _, err := Parse([]byte(bad)); err == nil {
		t.Fatal("expected error for duplicate OS id, got nil")
	}
}
