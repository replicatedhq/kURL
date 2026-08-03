package osmatrix

import (
	"strings"
	"testing"
)

const preflightFixture = `
oses:
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/noble.img
    preinit: ""
    preinitStyle: empty
    distro: ubuntu
    minKubernetes: "1.24"
    dockerSupported: false
    preflightName: Ubuntu
  - id: amazon-2023
    name: Amazon Linux
    version: "2023"
    vmimageuri: https://example.com/al2023.img
    preinit: ""
    preinitStyle: empty
    distro: amazonlinux
    minKubernetes: "1.24"
    dockerSupported: false
    preflightName: AmazonLinux
pools: []
`

func TestRenderPreflightDockerSupport(t *testing.T) {
	m := mustParse(t, preflightFixture)
	got := strings.Join(m.renderPreflightDockerSupport(), "\n")
	want := strings.Join([]string{
		"          - fail:",
		`              when: "ubuntu = 24.04"`,
		`              message: "Docker is not supported on Ubuntu 24.04"`,
		"          - fail:",
		`              when: "amazonlinux = 2023"`,
		`              message: "Docker is not supported on AmazonLinux 2023"`,
	}, "\n")
	if got != want {
		t.Errorf("docker support mismatch:\n got %q\nwant %q", got, want)
	}
}

func TestRenderPreflightKubernetesSupport(t *testing.T) {
	m := mustParse(t, preflightFixture)
	got := strings.Join(m.renderPreflightKubernetesSupport(), "\n")
	want := strings.Join([]string{
		"          - fail:",
		`              when: "ubuntu = 24.04"`,
		`              message: "Kubernetes versions < 1.24.0 are not supported on Ubuntu 24.04"`,
		"          - fail:",
		`              when: "amazonlinux = 2023"`,
		`              message: "Kubernetes versions < 1.24.0 are not supported on AmazonLinux 2023"`,
	}, "\n")
	if got != want {
		t.Errorf("k8s support mismatch:\n got %q\nwant %q", got, want)
	}
}

func TestPatchQualified(t *testing.T) {
	for in, want := range map[string]string{"1.24": "1.24.0", "1.24.0": "1.24.0", "2023": "2023"} {
		if got := patchQualified(in); got != want {
			t.Errorf("patchQualified(%q) = %q, want %q", in, got, want)
		}
	}
}
