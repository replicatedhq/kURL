package osmatrix

import "testing"

func TestRenderPool(t *testing.T) {
	m, err := Parse([]byte(testFixture))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	// os-latest: two entries (empty preinit, then quoted), no trailing newline.
	gotLatest, err := m.RenderPool("os-latest")
	if err != nil {
		t.Fatalf("RenderPool os-latest: %v", err)
	}
	wantLatest := `- id: ubuntu-1804
  name: Ubuntu
  version: "18.04"
  vmimageuri: https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img
  preinit: ""
- id: ubuntu-2404
  name: Ubuntu
  version: "24.04"
  vmimageuri: https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
  preinit: "apt-get update && apt-get install -y socat"`
	if string(gotLatest) != wantLatest {
		t.Errorf("os-latest mismatch:\n--- got ---\n%q\n--- want ---\n%q", gotLatest, wantLatest)
	}

	// os-min: single quoted entry, WITH trailing newline.
	gotMin, err := m.RenderPool("os-min")
	if err != nil {
		t.Fatalf("RenderPool os-min: %v", err)
	}
	wantMin := `- id: ubuntu-2404
  name: Ubuntu
  version: "24.04"
  vmimageuri: https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
  preinit: "apt-get update && apt-get install -y socat"
`
	if string(gotMin) != wantMin {
		t.Errorf("os-min mismatch:\n--- got ---\n%q\n--- want ---\n%q", gotMin, wantMin)
	}
}

func TestRenderOSBlockStyle(t *testing.T) {
	fixture := `
oses:
  - id: rocky-x
    name: Rocky Linux
    version: "9.8"
    vmimageuri: https://example.com/rocky.qcow2
    preinit: |
      yum install -y nfs-utils
      if ! foo; then
          bar
      fi
    preinitStyle: block
pools:
  - name: os-b
    trailingNewline: true
    ids: [rocky-x]
`
	m, err := Parse([]byte(fixture))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	got, err := m.RenderPool("os-b")
	if err != nil {
		t.Fatalf("RenderPool: %v", err)
	}
	want := `- id: rocky-x
  name: Rocky Linux
  version: "9.8"
  vmimageuri: https://example.com/rocky.qcow2
  preinit: |
    yum install -y nfs-utils
    if ! foo; then
        bar
    fi
`
	if string(got) != want {
		t.Errorf("block render mismatch:\n--- got ---\n%q\n--- want ---\n%q", got, want)
	}
}
