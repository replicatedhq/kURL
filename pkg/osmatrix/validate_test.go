package osmatrix

import (
	"strings"
	"testing"
)

func TestValidateAcceptsValidRegistry(t *testing.T) {
	// The real registry must pass validation unchanged.
	m, _ := loadRealMatrix(t)
	if err := m.validate(); err != nil {
		t.Fatalf("real registry failed validation: %v", err)
	}
}

func TestValidateRejectsInjection(t *testing.T) {
	cases := []struct {
		name, yaml, wantSubstr string
	}{
		{"id shell metachar", `
oses:
  - id: "ubuntu-2404$(touch pwned)"
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
pools: []`, "field id"},
		{"name newline", `
oses:
  - id: ubuntu-2404
    name: "Ubuntu\ninjected: key"
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
pools: []`, "field name"},
		{"vmimageuri metachar", `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: "https://e/x.img; rm -rf /"
    preinit: ""
    preinitStyle: empty
pools: []`, "field vmimageuri"},
		{"version backtick", "\noses:\n  - id: centos-x\n    name: CentOS\n    version: \"9`id`\"\n    vmimageuri: https://e/x.img\n    preinit: \"\"\n    preinitStyle: empty\npools: []", "field version"},
		{"minKubernetes newline", `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24\ninjected: key"
pools: []`, "field minKubernetes"},
		{"ubuntu version non-numeric", `
oses:
  - id: ubuntu-x
    name: Ubuntu
    version: "24.x"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
pools: []`, "ubuntu version"},
		{"quoted preinit newline", `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: "line1\nline2"
    preinitStyle: quoted
pools: []`, "quoted preinit must not contain a newline"},
		{"bad pool name", `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
pools:
  - name: "../../etc/passwd"
    ids: [ubuntu-2404]`, "pool name"},
		{"packageFamily metachar", `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
    packageFamily: "apt24 x"
pools: []`, "field packageFamily"},
	}
	for _, c := range cases {
		_, err := Parse([]byte(c.yaml))
		if err == nil {
			t.Errorf("%s: expected validation error, got nil", c.name)
			continue
		}
		if !strings.Contains(err.Error(), c.wantSubstr) {
			t.Errorf("%s: error %q does not mention %q", c.name, err, c.wantSubstr)
		}
	}
}

func TestValidateRejectsDivergentKubernetesFloor(t *testing.T) {
	y := `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/a.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
  - id: ubuntu-2604
    name: Ubuntu
    version: "26.04"
    vmimageuri: https://e/b.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.28"
pools: []`
	_, err := Parse([]byte(y))
	if err == nil || !strings.Contains(err.Error(), "divergent minKubernetes") {
		t.Fatalf("expected divergent-floor error, got %v", err)
	}
}

func TestValidateAcceptsNonUbuntuExoticVersions(t *testing.T) {
	// "stream", "2023", "8.x", "8.2024-04" must remain valid for non-ubuntu OSes.
	for _, v := range []string{"stream", "2023", "8.x", "8.2024-04", "10.2"} {
		y := "\noses:\n  - id: os-x\n    name: CentOS\n    version: \"" + v + "\"\n    vmimageuri: https://e/x.img\n    preinit: \"\"\n    preinitStyle: empty\npools: []"
		if _, err := Parse([]byte(y)); err != nil {
			t.Errorf("version %q should be valid for non-ubuntu OS: %v", v, err)
		}
	}
}
