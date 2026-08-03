package osmatrix

import (
	"strings"
	"testing"
)

const capFixture = `
oses:
  - id: ubuntu-2204
    name: Ubuntu
    version: "22.04"
    vmimageuri: https://example.com/jammy.img
    preinit: ""
    preinitStyle: empty
  - id: ubuntu-2404
    name: Ubuntu
    version: "24.04"
    vmimageuri: https://example.com/noble.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
    dockerSupported: false
  - id: ubuntu-2604
    name: Ubuntu
    version: "26.04"
    vmimageuri: https://example.com/resolute.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
    dockerSupported: false
  - id: amazon-2023
    name: Amazon Linux
    version: "2023"
    vmimageuri: https://example.com/al2023.img
    preinit: ""
    preinitStyle: empty
    minKubernetes: "1.24"
    dockerSupported: false
pools: []
`

func mustParse(t *testing.T, y string) *Matrix {
	t.Helper()
	m, err := Parse([]byte(y))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	return m
}

func TestOSesFailingMinKubernetes(t *testing.T) {
	m := mustParse(t, capFixture)

	cases := []struct {
		k8s  string
		want []string
	}{
		{"1.19.x", []string{"ubuntu-2404", "ubuntu-2604", "amazon-2023"}}, // < 1.24 => all min-constrained excluded
		{"1.23.0", []string{"ubuntu-2404", "ubuntu-2604", "amazon-2023"}},
		{"1.24.0", nil}, // == min => supported
		{"1.32.x", nil}, // > min
		{"latest", nil}, // unparseable => assume newest, not excluded
	}
	for _, tc := range cases {
		got := ids(m.OSesFailingMinKubernetes(tc.k8s))
		if !equalStrings(got, tc.want) {
			t.Errorf("OSesFailingMinKubernetes(%q) = %v, want %v", tc.k8s, got, tc.want)
		}
	}
}

func TestOSesWithoutDocker(t *testing.T) {
	m := mustParse(t, capFixture)
	got := ids(m.OSesWithoutDocker())
	want := []string{"ubuntu-2404", "ubuntu-2604", "amazon-2023"}
	if !equalStrings(got, want) {
		t.Errorf("OSesWithoutDocker() = %v, want %v", got, want)
	}
}

func TestCapabilityExcludedIDs(t *testing.T) {
	m := mustParse(t, capFixture)

	// Old k8s, no docker: excluded purely by minKubernetes.
	got := m.CapabilityExcludedIDs("1.19.x", false)
	want := []string{"ubuntu-2404", "ubuntu-2604", "amazon-2023"}
	if !equalStrings(got, want) {
		t.Errorf("k8s 1.19 no-docker = %v, want %v", got, want)
	}

	// New k8s but docker in use: excluded purely by dockerSupported=false.
	got = m.CapabilityExcludedIDs("1.32.x", true)
	if !equalStrings(got, want) {
		t.Errorf("k8s 1.32 docker = %v, want %v", got, want)
	}

	// New k8s, no docker: nothing capability-excluded.
	got = m.CapabilityExcludedIDs("1.32.x", false)
	if len(got) != 0 {
		t.Errorf("k8s 1.32 no-docker = %v, want empty", got)
	}

	// De-dup: an OS failing both rules appears once.
	got = m.CapabilityExcludedIDs("1.19.x", true)
	if !equalStrings(got, want) {
		t.Errorf("k8s 1.19 docker = %v, want %v (deduped)", got, want)
	}
	if strings.Count(strings.Join(got, ","), "ubuntu-2404") != 1 {
		t.Errorf("ubuntu-2404 should appear once, got %v", got)
	}
}

func ids(oses []*OS) []string {
	var out []string
	for _, o := range oses {
		out = append(out, o.ID)
	}
	return out
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
