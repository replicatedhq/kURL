package osmatrix

import (
	"fmt"
	"regexp"
	"strings"
)

const distroUbuntu = "ubuntu"

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
		if o.Distro == distroUbuntu && o.HostPackagesShipped {
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
		if o.Distro == distroUbuntu {
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

// familyHostPackageExclusionPredicates are the RHEL/Amazon FAMILY-level shell
// predicates that exclude an OS from host_packages_shipped, in committed order.
//
// Unlike the per-version apt predicates (is_ubuntu_<NN>04), which are data-driven
// from the registry's host-package-shipping Ubuntu entries, these are FAMILY
// predicates — is_rhel_9_variant matches EL 9/10 across centos|rhel|ol|rocky, and
// is_amazon_2023 matches Amazon Linux 2023 — whose definitions are hand-authored
// in scripts/common/host-packages.sh rather than generated per OS. They therefore
// cannot be derived from a single registry entry today.
//
// TODO(os-matrix, later convoy legs): once the Rocky/Oracle/Amazon-2023 registry
// entries carry a capability field naming their host-package-exclusion predicate,
// derive this list from the registry instead of hard-coding it. This pathfinder
// leg cannot: those entries are owned by later legs and must not be edited here.
var familyHostPackageExclusionPredicates = []string{"is_rhel_9_variant", "is_amazon_2023"}

// renderHostPackagesShippedGuard renders the single `if ...; then` line of
// host_packages_shipped: the fixed RHEL/Amazon family predicates followed by one
// data-driven `is_ubuntu_<NN>04` clause per host-package-shipping Ubuntu release.
func (m *Matrix) renderHostPackagesShippedGuard() []string {
	preds := append([]string(nil), familyHostPackageExclusionPredicates...)
	for _, o := range m.predicateUbuntuOSes() {
		preds = append(preds, predicateName(o))
	}
	clauses := make([]string, len(preds))
	for i, p := range preds {
		clauses[i] = "! " + p
	}
	return []string{"    if " + strings.Join(clauses, " && ") + "; then"}
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

var hostPackageCallRE = regexp.MustCompile(`^(\s*)ubuntu_\d+_install_host_packages\b[ \t]*(.*)$`)

// installHostPackagesFn is the ubuntu_<NN><NN>_install_host_packages function
// name for an Ubuntu OS.
func installHostPackagesFn(o *OS) string {
	return "ubuntu_" + versionDigits(o) + "_install_host_packages"
}

// renderUbuntuHostPackageCalls regenerates a host-package install region: one
// `ubuntu_<NN>04_install_host_packages <pkgs>` call per host-package-shipping
// Ubuntu release. The package list and indentation are taken from the region's
// current content (test-specific), so adding an Ubuntu release adds a matching
// call to every region without changing the packages. If the current region has
// no recognizable call, it is returned unchanged.
func (m *Matrix) renderUbuntuHostPackageCalls(current []string) []string {
	var indent, pkgs string
	found := false
	for _, l := range current {
		if mt := hostPackageCallRE.FindStringSubmatch(l); mt != nil {
			indent, pkgs = mt[1], mt[2]
			found = true
			break
		}
	}
	if !found {
		return current
	}
	var out []string
	for _, o := range m.predicateUbuntuOSes() {
		out = append(out, indent+installHostPackagesFn(o)+" "+pkgs)
	}
	return out
}

// apparmorUbuntuOSes returns the Ubuntu OSes needing the apparmor workaround, in
// registry order.
func (m *Matrix) apparmorUbuntuOSes() []*OS {
	var out []*OS
	for i := range m.OSes {
		o := &m.OSes[i]
		if o.Distro == distroUbuntu && o.ApparmorWorkaround {
			out = append(out, o)
		}
	}
	return out
}

// renderApparmorGuard renders the containerd apparmor guard line, e.g.
// "    if is_ubuntu_2404 || is_ubuntu_2604; then".
func (m *Matrix) renderApparmorGuard() []string {
	var preds []string
	for _, o := range m.apparmorUbuntuOSes() {
		preds = append(preds, predicateName(o))
	}
	return []string{"    if " + strings.Join(preds, " || ") + "; then"}
}

// renderContainerdScriptPreflights renders the ubuntu add_supported_os_to_preflight_file
// calls in addons/containerd/template/script.sh, one per host-package-shipping
// Ubuntu release.
func (m *Matrix) renderContainerdScriptPreflights() []string {
	var lines []string
	for _, o := range m.predicateUbuntuOSes() {
		lines = append(lines, fmt.Sprintf("        add_supported_os_to_preflight_file \"$version\" \"ubuntu\" \"=\" %q", o.Version))
	}
	return lines
}

// renderContainerdScriptManifests renders the ubuntu add_os_package_to_manifest_file
// calls in addons/containerd/template/script.sh, one per apt-family Ubuntu release.
func (m *Matrix) renderContainerdScriptManifests() []string {
	var lines []string
	for _, o := range m.predicateUbuntuOSes() {
		lines = append(lines, fmt.Sprintf("        add_os_package_to_manifest_file \"$version\" %q \"containerd\"", o.PackageFamily))
	}
	return lines
}

// aptOSes returns the OSes whose package family is an apt family, in registry
// order.
func (m *Matrix) aptOSes() []*OS {
	var out []*OS
	for i := range m.OSes {
		o := &m.OSes[i]
		if strings.HasPrefix(o.PackageFamily, "apt") {
			out = append(out, o)
		}
	}
	return out
}

// renderSaveManifestAptCases renders the apt<NN> case arms of
// bin/save-manifest-assets.sh, one per apt-family OS, separated by a blank line.
func (m *Matrix) renderSaveManifestAptCases() []string {
	var lines []string
	for i, o := range m.aptOSes() {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines,
			"        "+o.PackageFamily+")",
			"            mkdir -p \"$OUT_DIR\"/ubuntu-"+o.Version,
			"            package=$(echo \"$line\" | awk '{ print $2 }')",
			"            echo \"$package\" >> \"$OUT_DIR\"/ubuntu-"+o.Version+"/Deps",
			"            ;;",
		)
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
