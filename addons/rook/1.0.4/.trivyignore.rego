package trivy

import data.lib.trivy

default ignore = false

ignore {
	input.VulnerabilityID == "CVE-2021-20277"
	input.PkgName == "libldb"
  input.InstalledVersion == "1.5.4-2.el7"
  input.FixedVersion == "1.5.4-2.el7_9"
}
