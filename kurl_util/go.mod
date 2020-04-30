module github.com/replicatedhq/kurl/kurl_util

go 1.13

require (
	github.com/apparentlymart/go-cidr v1.0.1
	github.com/pkg/errors v0.8.1
	github.com/replicatedhq/kurl v0.0.0-20200429202312-cc019e10abc0 // indirect
	github.com/stretchr/testify v1.4.0
	github.com/vishvananda/netlink v0.0.0-20171020171820-b2de5d10e38e
	github.com/vishvananda/netns v0.0.0-20171111001504-be1fbeda1936 // indirect
	gopkg.in/yaml.v2 v2.2.8
	k8s.io/apimachinery v0.17.3
	k8s.io/client-go v0.17.2
)

replace (
	github.com/replicatedhq/kurl/ => ../
	github.com/replicatedhq/kurl/kurlkinds => ../kurlkinds
)
