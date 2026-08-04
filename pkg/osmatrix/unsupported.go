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
// A marked region is authoritative for its capability category: on regenerate it
// is rewritten to list EXACTLY the OSes the registry constrains for that category.
// Still-justified lines are preserved verbatim (so committed content, comments and
// all, is byte-identical), newly-constrained OSes are added, and OSes the registry
// no longer constrains — removed, or with the relevant constraint relaxed — are
// dropped. Adding an Ubuntu release to os-matrix.yaml therefore adds its exclusion
// line to every capability region, and relaxing/removing one shrinks it, while the
// TestGrid coverage matrix for existing OSes is provably unchanged (see
// TestGoldenMatrixSnapshot).

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

// capabilityAnchorRE matches a persisted category anchor: a comment-only line the
// generator leaves inside a region whose tracked category currently constrains no
// OS. A region's tracked categories are normally inferred from its exclusion
// lines, but if every constraint is relaxed the body shrinks to empty and that
// memory is lost -- a later constraint-add then has no category to grow into and
// the OS is silently omitted. The anchor carries the category across regenerate
// cycles so an emptied region still regrows correctly.
var capabilityAnchorRE = regexp.MustCompile(`^(\s*)#\s*os-matrix-capability-anchor:\s*(k8s|docker)\b`)

// capabilityAnchorCategory returns the category recorded by an anchor line, or ""
// if the line is not an anchor.
func capabilityAnchorCategory(line string) string {
	if mt := capabilityAnchorRE.FindStringSubmatch(line); mt != nil {
		return mt[2]
	}
	return ""
}

// capabilityAnchorLine renders the anchor comment for a tracked category that
// currently constrains no OS. The wording deliberately avoids the substrings
// capabilityCategory keys on, so an anchor is never mistaken for an exclusion.
func capabilityAnchorLine(indent, category string) string {
	reason := "no OS is currently constrained for this category"
	switch category {
	case categoryK8s:
		reason = "no OS currently declares a Kubernetes floor"
	case categoryDocker:
		reason = "no OS is currently without Docker support"
	}
	return fmt.Sprintf("%s# os-matrix-capability-anchor: %s (%s; kept so this region regrows if a constraint is added)", indent, category, reason)
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

// renderUnsupportedCapability regenerates a capability-exclusion region so it
// lists EXACTLY the OSes the registry currently constrains for the categories the
// region tracks. Still-justified exclusions keep their committed line verbatim
// (typos and all, so existing output stays byte-identical); an exclusion the
// registry no longer justifies — because the OS was removed OR its constraint for
// that category was relaxed — is dropped; a newly-constrained OS is appended under
// its own comment category. Both the shrink and grow sides operate per-category,
// so a region that mixes docker and Kubernetes-floor exclusions stays correct in
// both directions. Making the marked region authoritative (replace, not append)
// is what lets relaxing a constraint correctly SHRINK the exclusions.
// Hand-authored subset regions live outside the markers and are never passed here.
//
// If relaxing a constraint empties a tracked category entirely, a category anchor
// comment is left in its place so the region remembers what it tracks; a later
// regenerate that re-adds the constraint regrows the exclusion instead of
// forgetting the category and silently omitting the OS.
func (m *Matrix) renderUnsupportedCapability(current []string) []string {
	// First pass: find the indent and the categories this region tracks. A region
	// tracks a category if it has an exclusion line for it OR a persisted anchor
	// for it. The anchor is what lets a region that has shrunk to empty still
	// remember its category across regenerate cycles (without it, an emptied region
	// forgets what to grow and silently omits a later-re-added OS).
	indent := "  "
	indentSet := false
	setIndent := func(s string) {
		if !indentSet {
			indent = s
			indentSet = true
		}
	}
	trackedCats := map[string]bool{}
	for _, l := range current {
		if mt := unsupportedLineRE.FindStringSubmatch(l); mt != nil {
			setIndent(mt[1])
			if c := capabilityCategory(mt[3]); c != "" {
				trackedCats[c] = true
			}
			continue
		}
		if c := capabilityAnchorCategory(l); c != "" {
			setIndent(capabilityAnchorRE.FindStringSubmatch(l)[1])
			trackedCats[c] = true
		}
	}
	if len(trackedCats) == 0 {
		// Not a capability region (no exclusion lines, no anchors): leave as-is.
		return append([]string(nil), current...)
	}

	// A region may mix categories (an OS excluded for docker next to one excluded
	// for a Kubernetes floor), so BOTH sides work per-category: justify each line
	// against its OWN comment's category, and grow each category the region tracks.
	justified := map[string]map[string]bool{}
	for _, cat := range []string{categoryK8s, categoryDocker} {
		s := map[string]bool{}
		for _, id := range m.capabilityOSIDs(cat) {
			s[id] = true
		}
		justified[cat] = s
	}

	present := map[string]bool{} // every capability id in the region, for dedup by id
	var out []string
	for _, l := range current {
		mt := unsupportedLineRE.FindStringSubmatch(l)
		if mt != nil {
			if c := capabilityCategory(mt[3]); c != "" {
				// Keep the line only while the registry still constrains this OS
				// for the line's own category; otherwise drop it (OS removed or
				// its constraint for that category relaxed).
				if !justified[c][mt[2]] {
					continue
				}
				present[mt[2]] = true
				out = append(out, l)
				continue
			}
		}
		if capabilityAnchorCategory(l) != "" {
			continue // drop stale anchors; re-emitted below only where still needed
		}
		out = append(out, l) // non-capability, non-anchor line: preserve verbatim
	}
	// Grow every category the region tracks, symmetric with the shrink side, so a
	// newly-constrained OS of either category is appended under its own comment.
	// Dedup by id (an OS constrained by both categories is listed once, under the
	// first category encountered) so a region never gains a duplicate line.
	//
	// We deliberately grow ONLY categories the region already tracks. A category a
	// region does NOT track is one this spec has no exclusion rule for, and adding
	// one would wrongly skip a combination the matrix says should run. This is safe
	// for the k8s category because validate() forces a single shared floor: a
	// region without k8s lines belongs to a spec whose Kubernetes version is at or
	// above that floor (else it would already exclude the existing constrained
	// OSes), so a newly-added k8s-constrained OS — which shares that same floor — is
	// still supported there and must stay omitted. For docker it is safe because a
	// region without docker lines is a spec that does not use docker. Growing an
	// untracked category is therefore a golden-matrix regression, not a fix (see
	// TestRenderUnsupportedCapabilityDoesNotGrowUntrackedCategory).
	for _, c := range []string{categoryK8s, categoryDocker} {
		if !trackedCats[c] {
			continue
		}
		for _, id := range m.capabilityOSIDs(c) {
			if present[id] {
				continue
			}
			present[id] = true
			out = append(out, fmt.Sprintf("%s- %s # %s", indent, id, m.capabilityComment(c, id)))
		}
	}
	// If a tracked category currently constrains no OS, the shrink+grow above left
	// it with no line. Persist an anchor so the next regenerate still knows the
	// region tracks it and regrows when a constraint is re-added. (A category with
	// at least one constrained OS already has its line above, so needs no anchor —
	// keeping existing, populated regions byte-identical.)
	for _, c := range []string{categoryK8s, categoryDocker} {
		if trackedCats[c] && len(m.capabilityOSIDs(c)) == 0 {
			out = append(out, capabilityAnchorLine(indent, c))
		}
	}
	return out
}

// wrapCapabilityRuns is the ONE-TIME migration that introduced the bucket-2
// markers; it is invoked only from tests, not from the generate/check pipeline
// (that pipeline only re-fills already-marked regions via
// renderUnsupportedCapability). It wraps each maximal run of consecutive
// capability-exclusion lines that already lists the COMPLETE current capability
// set for its category. Only these "full" regions become generatable:
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
