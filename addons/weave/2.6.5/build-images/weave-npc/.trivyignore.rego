package trivy

import data.lib.trivy

default ignore = false

# this is not yet patched
# https://github.com/alpinelinux/docker-alpine/issues/264

ignore {
    input.PkgName == "busybox"
    input.VulnerabilityID == "CVE-2022-30065"
}

ignore {
    input.PkgName == "ssl_client"
    input.VulnerabilityID == "CVE-2022-30065"
}
