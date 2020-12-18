package types

type RunnerOptions struct {
	APIEndpoint string
}

type SingleRun struct {
	ID string

	OperatingSystemName    string
	OperatingSystemVersion string
	OperatingSystemImage   string

	PVCName string

	KurlYAML string
	KurlURL  string
	KurlRef  string

	TestGridAPIEndpoint string

	TimeoutAfter string
}
