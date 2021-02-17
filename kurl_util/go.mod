module github.com/replicatedhq/kurl/kurl_util

go 1.13

require (
	github.com/apparentlymart/go-cidr v1.1.0
	github.com/foomo/htpasswd v0.0.0-20200116085101-e3a90e78da9c
	github.com/pkg/errors v0.9.1
	github.com/replicatedhq/kurl v0.0.0-20210217182707-57fc33edb4cc
	github.com/replicatedhq/kurl/kurlkinds v0.0.0-20210217180730-2a5af0e23b74
	github.com/stretchr/testify v1.7.0
	github.com/vishvananda/netlink v0.0.0-20171020171820-b2de5d10e38e
	github.com/vishvananda/netns v0.0.0-20171111001504-be1fbeda1936 // indirect
	golang.org/x/crypto v0.0.0-20201002170205-7f63de1d35b0
	gopkg.in/yaml.v1 v1.0.0-20140924161607-9f9df34309c0
	gopkg.in/yaml.v2 v2.4.0
	k8s.io/apimachinery v0.20.2
	k8s.io/client-go v0.20.2
)

replace github.com/replicatedhq/kurl => ../

replace github.com/replicatedhq/kurl/kurl_util => ../kurl_util
