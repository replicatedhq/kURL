package osmatrix

import (
	"fmt"
	"regexp"
	"strings"
)

// This file generates the OS-capability subset of testgrid unsupportedOSIDs
// (bucket 2 of replicatedhq/kURL#6081). Capability exclusions — an OS excluded
// because the spec's Kubernetes version is below the OS's floor, or because the
// spec uses Docker which the OS does not support — are derived from the registry
// rather than hand-enumerated per spec. Spec-specific exclusions (a pinned kURL
// version, an addon-version constraint) stay hand-authored, outside the markers.
//
// The transform is conservative: it preserves every existing line in a region
// verbatim (so committed content, comments and all, is byte-identical) and only
// APPENDS a capability OS that is missing from the region. Adding an Ubuntu
// release to os-matrix.yaml therefore adds its exclusion line to every capability
// region on regenerate, while the TestGrid coverage matrix for existing OSes is
// provably unchanged (see TestGoldenMatrixSnapshot).

var unsupportedLineRE = regexp.MustCompile(`^(\s*)-\s+([A-Za-z0-9._-]+)\s*(#.*)?$`)

const (
	categoryK8s    = "k8s"
	categoryDocker = "docker"
)

// capabilityCategory classifies an unsupportedOSIDs comment as a Kubernetes-floor
// exclusion ("k8s"), a Docker-support exclusion ("docker"), or neither ("").
func capabilityCategory(comment string) string {
	c := strings.ToLower(comment)
	switch {
	case strings.Contains(c, "kubernetes versions <"):
		return categoryK8s
	case strings.Contains(c, "docker is not supported"):
		return categoryDocker
	default:
		return ""
	}
}

// capabilityOSIDs returns the OS ids (registry order) constrained by the given
// capability category.
func (m *Matrix) capabilityOSIDs(category string) []string {
	var out []string
	switch category {
	case categoryK8s:
		for i := range m.OSes {
			if m.OSes[i].MinKubernetes != "" {
				out = append(out, m.OSes[i].ID)
			}
		}
	case categoryDocker:
		for _, o := range m.OSesWithoutDocker() {
			out = append(out, o.ID)
		}
	}
	return out
}

// isCapabilityOSID reports whether id is constrained by any capability category
// (and so is eligible for generated exclusion).
func (m *Matrix) isCapabilityOSID(id string) bool {
	o, ok := m.OS(id)
	if !ok {
		return false
	}
	return o.MinKubernetes != "" || (o.DockerSupported != nil && !*o.DockerSupported)
}

// capabilityComment renders the canonical comment for a generated exclusion line.
func (m *Matrix) capabilityComment(category, id string) string {
	o, ok := m.OS(id)
	if !ok {
		return ""
	}
	switch category {
	case categoryK8s:
		return fmt.Sprintf("Kubernetes versions < %s are not supported on %s %s", o.MinKubernetes, o.Name, o.Version)
	case categoryDocker:
		return fmt.Sprintf("docker is not supported on %s %s", o.Name, o.Version)
	default:
		return ""
	}
}

// isCapabilityExclusionLine reports whether a line is a capability exclusion
// (an OS id the registry constrains, tagged with a capability comment).
func (m *Matrix) isCapabilityExclusionLine(line string) bool {
	mt := unsupportedLineRE.FindStringSubmatch(line)
	if mt == nil {
		return false
	}
	return m.isCapabilityOSID(mt[2]) && capabilityCategory(mt[3]) != ""
}

// renderUnsupportedCapability regenerates a capability-exclusion region:
// existing lines are preserved verbatim and any capability OS of the region's
// category that is missing is appended.
func (m *Matrix) renderUnsupportedCapability(current []string) []string {
	category := ""
	indent := "  "
	indentSet := false
	present := map[string]bool{}
	for _, l := range current {
		mt := unsupportedLineRE.FindStringSubmatch(l)
		if mt == nil {
			continue
		}
		if !indentSet {
			indent = mt[1]
			indentSet = true
		}
		present[mt[2]] = true
		if c := capabilityCategory(mt[3]); c != "" && category == "" {
			category = c
		}
	}
	out := append([]string(nil), current...)
	if category == "" {
		return out
	}
	for _, id := range m.capabilityOSIDs(category) {
		if !present[id] {
			out = append(out, fmt.Sprintf("%s- %s # %s", indent, id, m.capabilityComment(category, id)))
		}
	}
	return out
}

// wrapCapabilityRuns introduces BEGIN/END markers around each maximal run of
// consecutive capability-exclusion lines that already lists the COMPLETE current
// capability set for its category. Only these "full" regions become generatable:
// a spec that excludes just a subset of the capability OSes (e.g. only
// amazon-2023, because the others are excluded for another reason or predate the
// test) is intentionally not tracking the whole capability rule, so wrapping it
// would wrongly add OSes and change the coverage matrix. It is the one-time
// migration that makes the full regions generatable; thereafter
// renderUnsupportedCapability keeps them in sync. Content is otherwise unchanged.
func (m *Matrix) wrapCapabilityRuns(content []byte) []byte {
	const id = "unsupported-capability"
	hadTrailingNewline := strings.HasSuffix(string(content), "\n")
	text := strings.TrimSuffix(string(content), "\n")
	lines := strings.Split(text, "\n")

	var out []string
	i := 0
	for i < len(lines) {
		if !m.isCapabilityExclusionLine(lines[i]) {
			out = append(out, lines[i])
			i++
			continue
		}
		start := i
		var run []string
		for i < len(lines) && m.isCapabilityExclusionLine(lines[i]) {
			run = append(run, lines[i])
			i++
		}
		if m.runIsCompleteCapabilitySet(run) {
			indent := unsupportedLineRE.FindStringSubmatch(run[0])[1]
			out = append(out, indent+"# BEGIN GENERATED os-matrix: "+id+" — edit os-matrix.yaml, run 'make generate-os-matrix'")
			out = append(out, run...)
			out = append(out, indent+"# END GENERATED os-matrix: "+id)
		} else {
			// Subset run: leave hand-authored (avoid changing the matrix).
			out = append(out, lines[start:i]...)
		}
	}

	result := strings.Join(out, "\n")
	if hadTrailingNewline {
		result += "\n"
	}
	return []byte(result)
}

// runIsCompleteCapabilitySet reports whether a run of capability-exclusion lines
// contains every capability OS id of its (first line's) category — i.e. the run
// tracks the whole capability rule rather than a hand-picked subset.
func (m *Matrix) runIsCompleteCapabilitySet(run []string) bool {
	category := ""
	present := map[string]bool{}
	for _, l := range run {
		mt := unsupportedLineRE.FindStringSubmatch(l)
		if mt == nil {
			continue
		}
		present[mt[2]] = true
		if c := capabilityCategory(mt[3]); c != "" && category == "" {
			category = c
		}
	}
	if category == "" {
		return false
	}
	for _, id := range m.capabilityOSIDs(category) {
		if !present[id] {
			return false
		}
	}
	return true
}
