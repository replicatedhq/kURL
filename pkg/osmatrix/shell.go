package osmatrix

import "fmt"

// This file renders the OS-derived regions of the hand-maintained shell scripts
// (bucket 5 of replicatedhq/kURL#6081). Each renderer returns the lines that go
// between a region's BEGIN/END markers; the marker engine splices them into the
// committed file, leaving everything outside the markers byte-for-byte
// unchanged. Adding an Ubuntu release to os-matrix.yaml regenerates every region.

// predicateUbuntuOSes returns the Ubuntu OSes that need an is_ubuntu_<NN>04
// shell predicate: the ones for which kURL ships host packages. Returned in
// registry order.
func (m *Matrix) predicateUbuntuOSes() []*OS {
	var out []*OS
	for i := range m.OSes {
		o := &m.OSes[i]
		if o.Distro == "ubuntu" && o.HostPackagesShipped {
			out = append(out, o)
		}
	}
	return out
}

// ubuntuOSes returns every Ubuntu OS in the registry, in registry order.
func (m *Matrix) ubuntuOSes() []*OS {
	var out []*OS
	for i := range m.OSes {
		o := &m.OSes[i]
		if o.Distro == "ubuntu" {
			out = append(out, o)
		}
	}
	return out
}

// predicateName is the is_ubuntu_<NN><NN> function name for an Ubuntu OS,
// derived from its version (e.g. "24.04" -> is_ubuntu_2404).
func predicateName(o *OS) string {
	return "is_ubuntu_" + versionDigits(o)
}

// versionDigits is the Ubuntu version with the dot removed, e.g. "24.04" ->
// "2404".
func versionDigits(o *OS) string {
	out := make([]byte, 0, len(o.Version))
	for i := 0; i < len(o.Version); i++ {
		if o.Version[i] != '.' {
			out = append(out, o.Version[i])
		}
	}
	return string(out)
}

// renderHostPackagesPredicates renders the is_ubuntu_<NN>04 function definitions
// for scripts/common/host-packages.sh, separated by a blank line.
func (m *Matrix) renderHostPackagesPredicates() []string {
	var lines []string
	for i, o := range m.predicateUbuntuOSes() {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines,
			fmt.Sprintf("# %s returns 0 if the current distro is Ubuntu %s.", predicateName(o), o.Version),
			fmt.Sprintf("function %s() {", predicateName(o)),
			fmt.Sprintf("    if [ \"$DIST_VERSION_MAJOR\" != %q ]; then", o.VersionMajor),
			"        return 1",
			"    fi",
			"    if [ \"$LSB_DIST\" != \"ubuntu\" ]; then",
			"        return 1",
			"    fi",
			"    return 0",
			"}",
		)
	}
	return lines
}

// renderHostPackagesShippedGuard renders the single `if ...; then` line of
// host_packages_shipped, appending a `&& ! is_ubuntu_<NN>04` clause per
// host-package-shipping Ubuntu release.
func (m *Matrix) renderHostPackagesShippedGuard() []string {
	line := "    if ! is_rhel_9_variant && ! is_amazon_2023"
	for _, o := range m.predicateUbuntuOSes() {
		line += " && ! " + predicateName(o)
	}
	line += "; then"
	return []string{line}
}

// renderContainerdTestPredicates renders the is_ubuntu_<NN>04 test stubs for
// scripts/common/containerd-test.sh.
func (m *Matrix) renderContainerdTestPredicates() []string {
	var lines []string
	for _, o := range m.predicateUbuntuOSes() {
		lines = append(lines, fmt.Sprintf("function %s() { return \"${_IS_UBUNTU_%s:-1}\"; }",
			predicateName(o), versionDigits(o)))
	}
	return lines
}

// renderBailSupportedUbuntu renders the supported-Ubuntu case pattern line of
// bailIfUnsupportedOS in scripts/common/preflights.sh, e.g.
// "        ubuntu18.04|...|ubuntu26.04)".
func (m *Matrix) renderBailSupportedUbuntu() []string {
	line := "        "
	for i, o := range m.ubuntuOSes() {
		if i > 0 {
			line += "|"
		}
		line += "ubuntu" + o.Version
	}
	line += ")"
	return []string{line}
}
