package osmatrix

import "strconv"

// The capability engine computes, from the registry's declarative per-OS
// constraints, which OSes a given installer spec must exclude. This is the
// single source for the OS-capability subset of testgrid unsupportedOSIDs and
// for generated preflight rules — "computed from rules, not hand-enumerated".

// OSesFailingMinKubernetes returns the OSes (in registry order) whose
// MinKubernetes constraint is greater than the given Kubernetes version, i.e.
// the OSes on which that version is unsupported. An OS with no MinKubernetes is
// never returned. A version string that cannot be parsed (e.g. "latest") is
// treated as newest and excludes nothing.
func (m *Matrix) OSesFailingMinKubernetes(k8sVersion string) []*OS {
	specMajor, specMinor, ok := parseMajorMinor(k8sVersion)
	var out []*OS
	for i := range m.OSes {
		o := &m.OSes[i]
		if o.MinKubernetes == "" {
			continue
		}
		if !ok {
			continue // unparseable spec version => assume it satisfies the floor
		}
		minMajor, minMinor, minOK := parseMajorMinor(o.MinKubernetes)
		if !minOK {
			continue
		}
		if less(specMajor, specMinor, minMajor, minMinor) {
			out = append(out, o)
		}
	}
	return out
}

// OSesWithoutDocker returns the OSes (in registry order) that do not support
// Docker (DockerSupported explicitly false).
func (m *Matrix) OSesWithoutDocker() []*OS {
	var out []*OS
	for i := range m.OSes {
		o := &m.OSes[i]
		if o.DockerSupported != nil && !*o.DockerSupported {
			out = append(out, o)
		}
	}
	return out
}

// CapabilityExcludedIDs returns the testgrid OS ids that a spec with the given
// Kubernetes version and Docker usage must exclude per capability rules,
// de-duplicated and in registry order.
func (m *Matrix) CapabilityExcludedIDs(k8sVersion string, usesDocker bool) []string {
	excluded := make(map[string]bool)
	for _, o := range m.OSesFailingMinKubernetes(k8sVersion) {
		excluded[o.ID] = true
	}
	if usesDocker {
		for _, o := range m.OSesWithoutDocker() {
			excluded[o.ID] = true
		}
	}

	var out []string
	seen := make(map[string]bool)
	for i := range m.OSes {
		id := m.OSes[i].ID
		if excluded[id] && !seen[id] {
			out = append(out, id)
			seen[id] = true
		}
	}
	return out
}

// parseMajorMinor parses the leading "major.minor" of a Kubernetes version
// string such as "1.24", "1.19.x" or "1.32.0". ok is false when the first two
// dot-separated fields are not both integers.
func parseMajorMinor(v string) (major, minor int, ok bool) {
	field := func(s string) (int, string, bool) {
		i := 0
		for i < len(s) && s[i] != '.' {
			i++
		}
		n, err := strconv.Atoi(s[:i])
		if err != nil {
			return 0, "", false
		}
		rest := ""
		if i < len(s) {
			rest = s[i+1:]
		}
		return n, rest, true
	}

	major, rest, ok := field(v)
	if !ok {
		return 0, 0, false
	}
	minor, _, ok = field(rest)
	if !ok {
		return 0, 0, false
	}
	return major, minor, true
}

// less reports whether version (aMajor.aMinor) < (bMajor.bMinor).
func less(aMajor, aMinor, bMajor, bMinor int) bool {
	if aMajor != bMajor {
		return aMajor < bMajor
	}
	return aMinor < bMinor
}
