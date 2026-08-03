package osmatrix

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestRenderBundleDockerfile(t *testing.T) {
	fixture := `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/noble.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    bundleDockerfile: true
pools: []
`
	m := mustParse(t, fixture)
	o, _ := m.OS("ubuntu-2404")
	got, err := renderBundleDockerfile(o)
	if err != nil {
		t.Fatalf("renderBundleDockerfile: %v", err)
	}
	s := string(got)
	if !strings.HasPrefix(s, "FROM ubuntu:24.04\n") {
		t.Errorf("expected FROM ubuntu:24.04 first line, got %q", s[:min(40, len(s))])
	}
	if !strings.HasSuffix(s, "\n") {
		t.Error("expected trailing newline")
	}
	// The k8s package repo flow must be present and constant.
	if !strings.Contains(s, "ARG KUBERNETES_VERSION") || !strings.Contains(s, "/archives/Deps") {
		t.Error("rendered Dockerfile missing expected constant body")
	}
}

func TestBundleDockerfilePath(t *testing.T) {
	o := &OS{Version: "26.04"}
	if got := bundleDockerfilePath(o); got != filepath.Join("bundles", "k8s-ubuntu2604", "Dockerfile") {
		t.Errorf("bundleDockerfilePath = %q", got)
	}
}
