# this file exposes an output called "lint". inside this output all errors found
# during the lint process will be exposed. each error is composed by a message and
# a "field" property indicating where the error was found.
package kurl.installer

# reports an error in case the kubernetes distribution is k3s and the user has
# selected also a container runtime. for k3s no container runtime can be selected.
lint[output] {
	input.spec.k3s.version
	count(container_runtimes) > 0
	output :=  {
		"message": "container runtime is incompatible with k3s",
		"field": "spec.k3s"
	}
}

# reports an error in case the kubernetes distribution is rke2 and the user has
# also chosen a container runtime. for rke2 no container runtime can be selected.
lint[output] {
	input.spec.rke2.version
	count(container_runtimes) > 0
	output :=  {
		"message": "container runtime is incompatible with rke2",
		"field": "spec.rke2"
	}
}

# reports an error if user has selected the kubernetes distribution but has not
# selected a container runtime. a container runtime is necessary to run the kube
# distribution.
lint[output] {
	input.spec.kubernetes.version
	count(container_runtimes) == 0
	output :=  {
		"message": "no container runtime selected",
		"field": "spec"
	}
}

# reports an error if user has selected multiple container runtimes at the same
# time. only one can be selected (or docker or containerd).
lint[output] {
	count(container_runtimes) > 1
	output := {
		"message": "multiple container runtimes selected",
		"field": "spec"
	}
}

# checks if there is at least one selected kubernetes distro (kubernetes, k3s, or rke2).
lint[output] {
	count(kube_distributions) == 0
	output := {
		"message": "no kubernetes distribution selected",
		"field": "spec"
	}
}

# returns an error if more than one kubernetes distro has been selected.
lint[output] {
	count(kube_distributions) > 1
	output := {
		"message": "multiple kubernetes distributions selected",
		"field": "spec"
	}
}

# verifies if the selected kubernetes version is compatible with the selected container
# runtime. the only thing verified here is that we are not trying to run kubernetes 1.24+
# with the "docker" container runtime as they are incompatible.
lint[output] {
	not valid_runtime_for_kubernetes
	output := {
		"message": "kubernetes >= v1.24 does not work with docker",
		"field": "spec.docker"
	}
}

# verifies if the kubernetes service cidr override provided by the user is valid.
lint[output] {
	not valid_kubernetes_service_cidr_range_override
	output := {
		"message": "service cidr range is invalid",
		"field": "spec.kubernetes.serviceCidrRange"
	}
}

# verifies if the weave pod cidr range override provided by the user is valid.
lint[output] {
	not valid_pod_cidr_range_override("weave")
	output := {
		"message": "weave pod cidr range is invalid",
		"field": "spec.weave.podCidrRange"
	}
}

# verifies if the antrea pod cidr override provided by the user is valid.
lint[output] {
	not valid_pod_cidr_range_override("antrea")
	output := {
		"message": "antrea pod cidr range is invalid",
		"field": "spec.antrea.podCidrRange"
	}
}

# returns an error if the config has weave and antrea selected at the same time.
lint[output] {
	input.spec.weave.version
	input.spec.antrea.version
	output := {
		"message": "multiple cni plugins selected",
		"field": "spec"
	}
}

# returns an error if selected kubernetes is >= 1.20 and rook is less or equal to 1.0.4.
lint[output] {
	input.spec.rook
	is_addon_version_greater_than_or_equal("kubernetes", "1.20.0")
	not is_addon_version_greater_than("rook", "1.0.4")
	output := {
		"message": "rook 1.0.4 is not compatible with kubernetes 1.20+",
		"field": "spec.rook.version"
	}
}

# returns an error if longhorn <= 1.4.0 is selected with kubernetes >= 1.25.0, this
# pair is incompatible.
lint[output] {
	input.spec.longhorn
	is_addon_version_greater_than_or_equal("kubernetes", "1.25.0")
	not is_addon_version_greater_than("longhorn", "1.4.0")
	output := {
		"message": "longhorn <= 1.4.0 are not compatible with kubernetes 1.25+",
		"field": "spec.longhorn.version"
	}
}

# this returns an error if an invalid or unknown version for an add-on has been selected.
lint[output] {
	some name 
	ignored := known_versions[name]
	not valid_add_on_version(name)
	output := {
		"message": sprintf("unknown %v version %v", [name, input.spec[name].version]),
		"field": sprintf("spec.%v.version", [name])
	}
}
