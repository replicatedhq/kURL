# Copyright 2022 Replicated Inc.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# 	http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
package kurl.installer

# kube_distributions holds an array of all selected kubernetes "distributions" (kubernetes, k3s,
# or rke2). this is useful if we want to check how many got selected and return an error if more
# than one has been selected.
kube_distributions[distro] {
	input.spec.kubernetes.version
	distro := "kubernetes"
}
kube_distributions[distro] {
	input.spec.k3s.version
	distro := "k3s"
}
kube_distributions[distro] {
	input.spec.rke2.version
	distro := "rke2"
}

# container_runtime gather the selected container runtimes in an array. we use this to evaluate
# how many of them got selected.
container_runtimes[runtime] {
	input.spec.docker.version
	runtime := "docker"
}
container_runtimes[runtime] {
	input.spec.containerd.version
	runtime := "containerd"
}

# evaluates to true if the given addon has its version is lower (older) than or equal to the
# provided semantic version.
is_addon_version_lower_than_or_equal(addon, version) {
	no_latest := replace(input.spec[addon].version, "latest", known_versions[addon].latest)
	no_version_x := replace(no_latest, ".x", ".999")
	semver.compare(no_version_x, version) <= 0
}

# evaluates to true if the given addon has its version is lower (older) than the provided
# semantic version.
is_addon_version_lower_than(addon, version) {
	no_latest := replace(input.spec[addon].version, "latest", known_versions[addon].latest)
	no_version_x := replace(no_latest, ".x", ".999")
	semver.compare(no_version_x, version) < 0
}

# evaluates to true if the given addon has its version is greater than or equal to the provided
# semantic version.
is_addon_version_greater_than_or_equal(addon, version) {
	no_latest := replace(input.spec[addon].version, "latest", known_versions[addon].latest)
	no_version_x := replace(no_latest, ".x", ".999")
	semver.compare(no_version_x, version) >= 0
}

# evaluates to true if the given addon has its version is greater than to the provided semantic
# version.
is_addon_version_greater_than(addon, version) {
	no_latest := replace(input.spec[addon].version, "latest", known_versions[addon].latest)
	no_version_x := replace(no_latest, ".x", ".999")
	semver.compare(no_version_x, version) > 0
}

# addon_version_exists checks if provided addon supports the provided version. if version
# is "latest" then this evaluates to true, if it is an static version it checks if the version
# exists and if it is a "x" version it makes sure at least one version exists in the x range.
# if an override (s3Override) has been provided to the add-on this will evaluates to true.
addon_version_exists(addon, version) {
	version == "latest"
}
addon_version_exists(addon, version) {
	input.spec[addon].s3Override
}
addon_version_exists(addon, version) {
	known_versions[addon].versions[_] == version
}
addon_version_exists(addon, version) {
	endswith(version, "x")
	x_version_removed := replace(version, "x", "")
	startswith(known_versions[addon].versions[_], x_version_removed)
}

# valid_cidr evaluates to true if argument (string) is a valid cidr. XXX I could not find
# a function to properly validate a CIDR and the approach of getting a list of IPs [1] works
# but may generate a dos if the address space is too big. Implementing it using regex seems
# fine. another approach could be done by registering a custom builtin function [2] but that
# would make the rego files not compatible with oficial parsers, keeping the implementation
# here in case we resolve to force users to use our own Lint() function (instead of using
# the .rego files directly).
#
# [1]:
# ips := net.cidr_expand(input.spec.kubernetes.serviceCidrRange)
# count(ips) >= 256
#
# [2]:
# go code:
# rego.RegisterBuiltin1(
#	&rego.Function{
#		Name: "net.cidr_parse",
#		Decl: types.NewFunction([]types.Type{types.S}, types.B),
#	},
#	func(bctx rego.BuiltinContext, op *ast.Term) (*ast.Term, error) {
#		cidr, err := builtins.StringOperand(op.Value, 1)
#		if err != nil {
#			return ast.BooleanTerm(false), err
#		}
#
#		if _, _, err := net.ParseCIDR(string(cidr)); err != nil {
#			return ast.BooleanTerm(false), nil
#		}
#		return ast.BooleanTerm(true), nil
#	},
# )
# rego code:
# net.cidr_parse(cidr)
valid_cidr(cidr) {
	regex.match(`^\d+\.\d+\.\d+\.\d+\/\d+$`, cidr)
}

# valid_kubernetes_service_cidr_range_override checks if the service cidr range override has
# been passed on by the user and if it is valid.
valid_kubernetes_service_cidr_range_override {
	not input.spec.kubernetes.serviceCidrRange
}
valid_kubernetes_service_cidr_range_override {
	valid_cidr(input.spec.kubernetes.serviceCidrRange)
}

# valid_pod_cidr_range_override checks id the provided podCidrRange property represents a valid
# net range.
valid_pod_cidr_range_override(addon) {
	not input.spec[addon].podCidrRange
}
valid_pod_cidr_range_override(addon) {
	valid_cidr(input.spec[addon].podCidrRange)
}

# valid_runtime_for_kubernetes checks if the selected container runtime is accepted by
# the kubernetes. if kubernetes version is greater or equal to v1.24 then containerd
# must be the chosen runtime. this is equivalent to:
#
# 	return version < 1.24 || container_runtime == "containerd"
#
valid_runtime_for_kubernetes {
	not is_addon_version_greater_than_or_equal("kubernetes", "1.24.0")
}
valid_runtime_for_kubernetes {
	input.spec.containerd.version
}

# valid_addon_version checks if the version for the addon exists (is valid). if the addon
# has not been selected (there is no version specified for it) then this evaluates to true.
valid_add_on_version(addon) {
	not input.spec[addon].version
}
valid_add_on_version(addon) {
	addon_version_exists(addon, input.spec[addon].version)
}

# add_on_compatible_with_k3s evaluates to true if the provided addon is compatible with
# k3s distribution.
add_on_compatible_with_k3s(addon) {
	compatible := [
		"k3s",
		"kotsadm",
		"minio",
		"openebs",
		"registry",
		"rook",
		"sonobuoy"
	]
	compatible[_] == addon
}

# add_on_compatible_with_rke2 evaluates to true if the provided addon is compatible with
# rke2 distribution.
add_on_compatible_with_rke2(addon) {
	compatible := [
		"rke2",
		"kotsadm",
		"minio",
		"openebs",
		"velero",
		"registry",
		"rook",
		"sonobuoy"
	]
	compatible[_] == addon
}

# port_out_of_range evaluates to true if provided port is out of provided range. 
port_out_of_range(port, floor, ceil) {
	port < floor
}
port_out_of_range(port, floor, ceil) {
	port > ceil
}

