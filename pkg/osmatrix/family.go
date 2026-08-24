package osmatrix

import (
	"fmt"
	"strings"
)

// This file renders the shared distro-family shell predicates (is_<name>) from the
// registry's `families` table into the generated region in
// scripts/common/host-packages.sh. A family predicate matches on $LSB_DIST and
// $DIST_VERSION_MAJOR and is called both by hand-written installer code and by the
// generated host_packages_shipped guard. Adding a family (or a member distro/major)
// is a registry edit plus `make generate-os-matrix`.

// renderFamilyPredicates renders every family's is_<predicate> function
// definition, in registry order, separated by a blank line.
func (m *Matrix) renderFamilyPredicates() []string {
	var lines []string
	for i := range m.Families {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, renderFamilyPredicate(&m.Families[i])...)
	}
	return lines
}

// renderFamilyPredicate renders one family's shell predicate. The version-major
// guard is an &&-chain of `!=` tests (one per major). The distro guard is a single
// `!=` test when the family matches one $LSB_DIST token, or a `case` when it
// matches several (the multi-distro form carries a leading blank line, matching the
// hand-authored originals byte-for-byte).
func renderFamilyPredicate(f *Family) []string {
	lines := []string{
		fmt.Sprintf("# %s returns 0 if the current distro is %s", f.Predicate, f.Description),
		fmt.Sprintf("function %s() {", f.Predicate),
	}

	majorClauses := make([]string, len(f.VersionMajors))
	for i, v := range f.VersionMajors {
		majorClauses[i] = fmt.Sprintf("[ \"$DIST_VERSION_MAJOR\" != %q ]", v)
	}
	lines = append(lines,
		"    if "+strings.Join(majorClauses, " && ")+"; then",
		"        return 1",
		"    fi",
	)

	if len(f.LSBDist) == 1 {
		lines = append(lines,
			fmt.Sprintf("    if [ \"$LSB_DIST\" != %q ]; then", f.LSBDist[0]),
			"        return 1",
			"    fi",
			"    return 0",
		)
	} else {
		lines = append(lines,
			"",
			`    case "$LSB_DIST" in`,
			"        "+strings.Join(f.LSBDist, "|")+")",
			"            return 0",
			"            ;;",
			"        *)",
			"            return 1",
			"            ;;",
			"    esac",
		)
	}

	lines = append(lines, "}")
	return lines
}
