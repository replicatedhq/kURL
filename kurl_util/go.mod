module github.com/replicatedhq/kurl/kurl_util

go 1.13

require (
	github.com/apparentlymart/go-cidr v1.0.1
	github.com/coreos/bbolt v1.3.1-coreos.6 // indirect
	github.com/coreos/etcd v3.3.15+incompatible // indirect
	github.com/foomo/htpasswd v0.0.0-20200116085101-e3a90e78da9c // indirect
	github.com/pkg/errors v0.8.1
	github.com/replicatedhq/kurl v0.0.0-20200601170456-4d9730fe4307
	github.com/replicatedhq/kurl/kurlkinds v0.0.0-20200721181735-b9a1f8cea03b
	github.com/stretchr/testify v1.4.0
	github.com/vishvananda/netlink v0.0.0-20171020171820-b2de5d10e38e
	github.com/vishvananda/netns v0.0.0-20171111001504-be1fbeda1936 // indirect
	golang.org/x/crypto v0.0.0-20200220183623-bac4c82f6975
	gonum.org/v1/netlib v0.0.0-20190331212654-76723241ea4e // indirect
	gopkg.in/yaml.v2 v2.2.8
	k8s.io/apimachinery v0.18.3
	k8s.io/client-go v0.18.3
	sigs.k8s.io/structured-merge-diff v1.0.1-0.20191108220359-b1b620dd3f06 // indirect
	sigs.k8s.io/testing_frameworks v0.1.2 // indirect
)

replace github.com/replicatedhq/kurl/ => ../
