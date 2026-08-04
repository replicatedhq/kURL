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
	cases := map[string]string{
		"id shell metachar": `
oses:
  - id: "ubuntu-2404$(touch pwned)"
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
pools: []`,
		"name newline": `
oses:
  - id: ubuntu-2404
    name: "Ubuntu\ninjected: key"
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
pools: []`,
		"vmimageuri metachar": `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: "https://e/x.img; rm -rf /"
    preinit: ""
    preinitStyle: empty
pools: []`,
		"version backtick": "\noses:\n  - id: ubuntu-2404\n    name: Ubuntu\n    version: \"24.04`id`\"\n    vmimageuri: https://e/x.img\n    preinit: \"\"\n    preinitStyle: empty\npools: []",
		"ubuntu version non-numeric": `
oses:
  - id: ubuntu-x
    name: Ubuntu
    version: "24.x"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
pools: []`,
		"quoted preinit newline": `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: "line1\nline2"
    preinitStyle: quoted
pools: []`,
		"bad pool name": `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
pools:
  - name: "../../etc/passwd"
    ids: [ubuntu-2404]`,
		"packageFamily metachar": `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/x.img
    preinit: ""
    preinitStyle: empty
    packageFamily: "apt24 x"
pools: []`,
	}
	for name, y := range cases {
		if _, err := Parse([]byte(y)); err == nil {
			t.Errorf("%s: expected validation error, got nil", name)
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
