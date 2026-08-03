package osmatrix

import (
	"strings"
	"testing"
)

const buildFixture = `
oses:
  - id: ubuntu-2204
    name: Ubuntu
    version: "22.04"
    vmimageuri: https://e/j.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://e/n.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    packageFamily: apt24
    bundleDockerfile: true
  - id: ubuntu-2604
    name: Ubuntu
    version: "26.04"
    vmimageuri: https://e/r.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    packageFamily: apt26
    bundleDockerfile: true
pools: []
`

func TestRenderMakefileDistList(t *testing.T) {
	m := mustParse(t, buildFixture)
	got := strings.Join(m.renderMakefileDistList(), "\n")
	want := "\t${MAKE} build/packages/kubernetes/$*/ubuntu-22.04\n" +
		"\t${MAKE} build/packages/kubernetes/$*/ubuntu-24.04\n" +
		"\t${MAKE} build/packages/kubernetes/$*/ubuntu-26.04"
	if got != want {
		t.Errorf("dist list:\n got %q\nwant %q", got, want)
	}
}

func TestRenderMakefileModernTargets(t *testing.T) {
	m := mustParse(t, buildFixture)
	got := strings.Join(m.renderMakefileModernTargets(), "\n")
	// Only bundleDockerfile OSes (2404, 2604), template substituted, blank-separated.
	if !strings.Contains(got, "build/packages/kubernetes/%/ubuntu-24.04:") ||
		!strings.Contains(got, "build/packages/kubernetes/%/ubuntu-26.04:") {
		t.Errorf("expected both modern targets, got:\n%s", got)
	}
	if strings.Contains(got, "ubuntu-22.04:") {
		t.Error("non-bundle ubuntu-22.04 should not get a modern target")
	}
	if !strings.Contains(got, "-f bundles/k8s-ubuntu2604/Dockerfile") {
		t.Error("template DIG substitution wrong for 2604")
	}
}

func TestRenderSaveManifestAptCases(t *testing.T) {
	m := mustParse(t, buildFixture)
	got := strings.Join(m.renderSaveManifestAptCases(), "\n")
	want := "        apt24)\n" +
		"            mkdir -p \"$OUT_DIR\"/ubuntu-24.04\n" +
		"            package=$(echo \"$line\" | awk '{ print $2 }')\n" +
		"            echo \"$package\" >> \"$OUT_DIR\"/ubuntu-24.04/Deps\n" +
		"            ;;\n" +
		"\n" +
		"        apt26)\n" +
		"            mkdir -p \"$OUT_DIR\"/ubuntu-26.04\n" +
		"            package=$(echo \"$line\" | awk '{ print $2 }')\n" +
		"            echo \"$package\" >> \"$OUT_DIR\"/ubuntu-26.04/Deps\n" +
		"            ;;"
	if got != want {
		t.Errorf("apt cases:\n got %q\nwant %q", got, want)
	}
}
