package types

type RunnerOptions struct {
	APIEndpoint string
	APIToken    string
}

type SingleRun struct {
	ID string

	OperatingSystemName    string
	OperatingSystemVersion string
	OperatingSystemImage   string
	OperatingSystemPreInit string

	PVCName string

	KurlYAML          string
	KurlURL           string
	KurlFlags         string
	UpgradeURL        string
	SupportbundleYAML string
	PostInstallScript string
	PostUpgradeScript string
	KurlRef           string

	TestGridAPIEndpoint string
}
