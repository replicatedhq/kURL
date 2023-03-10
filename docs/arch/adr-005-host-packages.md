# ADR 5: Host Packages

## Context

Today, kURL bundles all host OS packages and their sub-dependencies in the add-on packages it generates and installs these packages in the end customer environment, rather than directly from the package repositories.

For RPM based distributions, kURL sets up a local "kurl.local" repository and overrides the official OS mirrors for dependency resolution when installing these packages.
Even worse, for APT based distributions, kURL uses the `dpkg` command rather than `apt`, forgoes dependency resolution, and force installs the packages, often breaking the dependency graph.

This negatively affects the end customer, as dependency incompatibilities can result in broken OS packages, and often prevent upgrading the host OS when applying upgrades and security patches.
Additionally, this is an unsupported means of installing, likely nullifying enterprise support contracts with the host OS provider.
Finally, packaging an entirely new dependency chain for each host OS and version results in a significant amount of data (on the order of gigabytes) that must be downloaded and stored by the end customer each time they want to run a kURL install or upgrade.

For us, the maintainers of kURL, this "feature" has its own set of challenges.
Since host packages are targeted to OS and version, this requires additional work from the team to add support for each new OS and version.
Additionally, as kURL is taking ownership of these OS packages, each supported OS must be added to the test matrix, adding significant time and cost to Testgrid.

## Decision

Rather than bundle host packages in the add-on archive, kURL will install the required packages using the official repos already available to the host.

## Solution

It is likely that the server already has access to official mirrors or satellite package repositories.
If the packages are available in a repository, then kURL will install the packages from there.

A set of preflights will be run at the start of installation to determine if any of the packages are not available.
If not available, the script will exit early with a friendly message to the user detailing the missing packages, including a command to install these packages.
In addition to these preflights, we must document host OS package requirements in the kURL add-on documentation.

kURL will treat add-ons that are host packages themselves a bit differently (Containerd, Docker, Kubernetes Kubelet, Collectd).
These will continue to be bundled along with the add-on archive and installed from the bundle as we do today.
Sub-dependencies will no longer be packaged along with the add-on archive and will be installed from remote repositories.

We will roll this solution out for new host OS versions.
We will continue to support existing host OS versions as we did prior to this proposal.
Existing installations that update to a newer host OS version will be forced into the proposed host OS package support. 

## Status

Accepted

## Consequences

kURL will install packages from official mirrors rather than ones included in the add-on archive.

kURL will install the most up-to-date host packages available rather than the ones available at the time the add-on archive was built.
If the end-customer prefers specific versions, they can run `yum versionlock` or `apt-hold` to pin those package versions.

Significantly smaller add-on packages and airgap bundles, resulting in reduced download times for the end customer.

Reduced testing surface area, resulting in savings of both time and cost from Testgrid.

Airgapped environments must have access to package repositories or the end customer will have to manually install the required packages, possibly resulting in longer time to a live installation.
The customer may have to open IP addresses and ports in their corporate/gateway/network allowlist to enable the OS package manager to download the required packages.

Any unforeseen challenges installing host packages from remote repositories in a secure environment.

Existing installations that update to a newer host OS version will be forced into the proposed host OS package support.

We must maintain documentation of host OS package requirements in the kURL add-on documentation.
