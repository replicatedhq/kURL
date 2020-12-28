module github.com/replicatedhq/kurl/kurl_util

go 1.13

require (
	github.com/apparentlymart/go-cidr v1.0.1
	github.com/foomo/htpasswd v0.0.0-20200116085101-e3a90e78da9c
	github.com/pkg/errors v0.8.1
	github.com/replicatedhq/kurl v0.0.0-20200601170456-4d9730fe4307
	github.com/replicatedhq/kurl/kurlkinds v0.0.0-20201228201742-70dbb411b59c
	github.com/stretchr/testify v1.4.0
	github.com/vishvananda/netlink v0.0.0-20171020171820-b2de5d10e38e
	github.com/vishvananda/netns v0.0.0-20171111001504-be1fbeda1936 // indirect
	golang.org/x/crypto v0.0.0-20200220183623-bac4c82f6975
	gopkg.in/yaml.v1 v1.0.0-20140924161607-9f9df34309c0
	gopkg.in/yaml.v2 v2.2.8
	k8s.io/apimachinery v0.18.3
	k8s.io/client-go v0.18.3
)

replace github.com/replicatedhq/kurl/ => ../
