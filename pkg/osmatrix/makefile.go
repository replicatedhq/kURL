package osmatrix

import "strings"

// This file renders the OS-derived regions of the Makefile (bucket 6 of
// replicatedhq/kURL#6081): the list of per-Ubuntu kubernetes-package build
// invocations, and the modern (apt-bundle) per-Ubuntu build targets. Both are
// marker regions kept in sync with os-matrix.yaml, so adding a modern Ubuntu
// release is a registry entry plus regenerate rather than a hand-copied target.

// makefileModernTargetTemplate is the single source for a modern Ubuntu k8s
// build target. __VER__ is the OS version ("24.04"); __DIG__ is the dotless form
// ("2404"). The 24.04 and 26.04 targets on main are identical modulo these.
const makefileModernTargetTemplate = `build/packages/kubernetes/%/ubuntu-__VER__:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
		-t kurl/ubuntu-__DIG__-k8s:$* \
		-f bundles/k8s-ubuntu__DIG__/Dockerfile \
		bundles/k8s-ubuntu__DIG__
	-docker rm -f k8s-ubuntu__DIG__-$* 2>/dev/null
	docker create --name k8s-ubuntu__DIG__-$* kurl/ubuntu-__DIG__-k8s:$*
	mkdir -p build/packages/kubernetes/$*/ubuntu-__VER__
	docker cp k8s-ubuntu__DIG__-$*:/archives/. build/packages/kubernetes/$*/ubuntu-__VER__/
	docker rm k8s-ubuntu__DIG__-$*`

// renderMakefileDistList renders the per-Ubuntu build invocations under
// dist/kubernetes-%.tar.gz, one tab-indented `${MAKE} ...` line per Ubuntu OS.
func (m *Matrix) renderMakefileDistList() []string {
	var lines []string
	for _, o := range m.ubuntuOSes() {
		lines = append(lines, "\t${MAKE} build/packages/kubernetes/$*/ubuntu-"+o.Version)
	}
	return lines
}

// renderMakefileModernTargets renders the modern per-Ubuntu build targets (the
// bundleDockerfile OSes), separated by a blank line.
func (m *Matrix) renderMakefileModernTargets() []string {
	var lines []string
	first := true
	for i := range m.OSes {
		o := &m.OSes[i]
		if !o.BundleDockerfile {
			continue
		}
		if !first {
			lines = append(lines, "")
		}
		first = false
		block := makefileModernTargetTemplate
		block = strings.ReplaceAll(block, "__VER__", o.Version)
		block = strings.ReplaceAll(block, "__DIG__", versionDigits(o))
		lines = append(lines, strings.Split(block, "\n")...)
	}
	return lines
}
