package osmatrix

import "fmt"

// This file renders the OS-derived fail outcomes of the built-in host preflights
// (bucket 4 of replicatedhq/kURL#6081) from the registry's capability fields.
// The regions live in pkg/preflight/assets/host-preflights.yaml under the
// "Docker Support" and "Kubernetes Support" hostOS checks.

// preflightFailIndent is the indentation of a `- fail:` outcome entry in
// host-preflights.yaml.
const preflightFailIndent = "          "

// renderPreflightFail renders one host-preflight fail outcome.
func renderPreflightFail(o *OS, message string) []string {
	return []string{
		preflightFailIndent + "- fail:",
		preflightFailIndent + fmt.Sprintf("    when: %q", fmt.Sprintf("%s = %s", o.Distro, o.Version)),
		preflightFailIndent + fmt.Sprintf("    message: %q", message),
	}
}

// renderPreflightDockerSupport renders the fail outcomes for OSes that do not
// support Docker.
func (m *Matrix) renderPreflightDockerSupport() []string {
	var lines []string
	for _, o := range m.OSesWithoutDocker() {
		msg := fmt.Sprintf("Docker is not supported on %s %s", o.preflightDisplay(), o.Version)
		lines = append(lines, renderPreflightFail(o, msg)...)
	}
	return lines
}

// renderPreflightKubernetesSupport renders the fail outcomes for OSes with a
// minimum-Kubernetes constraint. All constrained OSes must share the same floor
// (the check's single exclude clause encodes one floor); this panics via the
// generator error path otherwise.
func (m *Matrix) renderPreflightKubernetesSupport() []string {
	floor := m.commonKubernetesFloor()
	var lines []string
	for i := range m.OSes {
		o := &m.OSes[i]
		if o.MinKubernetes == "" {
			continue
		}
		msg := fmt.Sprintf("Kubernetes versions < %s are not supported on %s %s",
			floor, o.preflightDisplay(), o.Version)
		lines = append(lines, renderPreflightFail(o, msg)...)
	}
	return lines
}

// commonKubernetesFloor returns the patch-qualified Kubernetes floor shared by
// all min-constrained OSes (e.g. "1.24" -> "1.24.0"). Returns "" if none.
// Matrix.validate guarantees all min-constrained OSes share one floor, so
// taking the first is safe — divergent floors fail at Parse, not here.
func (m *Matrix) commonKubernetesFloor() string {
	floor := ""
	for i := range m.OSes {
		if v := m.OSes[i].MinKubernetes; v != "" {
			if floor == "" {
				floor = v
			}
		}
	}
	if floor == "" {
		return ""
	}
	return patchQualified(floor)
}

// preflightDisplay is the OS's display name in preflight messages, defaulting to
// Name when PreflightName is unset.
func (o *OS) preflightDisplay() string {
	if o.PreflightName != "" {
		return o.PreflightName
	}
	return o.Name
}

// patchQualified appends ".0" to a bare "major.minor" version.
func patchQualified(v string) string {
	dots := 0
	for i := 0; i < len(v); i++ {
		if v[i] == '.' {
			dots++
		}
	}
	if dots == 1 {
		return v + ".0"
	}
	return v
}
