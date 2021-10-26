module github.com/replicatedhq/kurl

go 1.16

require (
	github.com/Masterminds/goutils v1.1.1 // indirect
	github.com/Masterminds/semver v1.5.0 // indirect
	github.com/Masterminds/sprig v2.22.0+incompatible
	github.com/apparentlymart/go-cidr v1.1.0
	github.com/aws/aws-sdk-go v1.40.11 // indirect
	github.com/briandowns/spinner v1.16.0
	github.com/bugsnag/bugsnag-go/v2 v2.1.1
	github.com/chzyer/readline v0.0.0-20180603132655-2972be24d48e
	github.com/containers/image/v5 v5.10.4
	github.com/denisbrodbeck/machineid v1.0.1
	github.com/evanphx/json-patch v4.11.0+incompatible // indirect
	github.com/fatih/color v1.12.0
	github.com/foomo/htpasswd v0.0.0-20200116085101-e3a90e78da9c
	github.com/go-ini/ini v1.62.0 // indirect
	github.com/go-logr/zapr v0.4.0 // indirect
	github.com/golang/groupcache v0.0.0-20210331224755-41bb18bfe9da // indirect
	github.com/golang/mock v1.6.0
	github.com/google/uuid v1.2.0 // indirect
	github.com/googleapis/gnostic v0.5.5 // indirect
	github.com/gorilla/mux v1.8.0
	github.com/huandu/xstrings v1.3.2 // indirect
	github.com/imdario/mergo v0.3.12 // indirect
	github.com/itchyny/gojq v0.12.4
	github.com/mattn/go-isatty v0.0.13
	github.com/minio/minio-go v6.0.14+incompatible
	github.com/mitchellh/copystructure v1.2.0 // indirect
	github.com/onsi/gomega v1.15.0
	github.com/pelletier/go-toml v1.9.3
	github.com/pkg/errors v0.9.1
	github.com/prometheus/common v0.29.0 // indirect
	github.com/replicatedhq/pvmigrate v0.3.1
	github.com/replicatedhq/troubleshoot v0.16.0
	github.com/sirupsen/logrus v1.8.1
	github.com/spf13/afero v1.6.0
	github.com/spf13/cobra v1.2.1
	github.com/spf13/viper v1.8.1
	github.com/stretchr/testify v1.7.0
	github.com/vishvananda/netlink v1.1.0
	github.com/vmware-tanzu/velero v1.6.2
	golang.org/x/crypto v0.0.0-20210513164829-c07d793c2f9a
	golang.org/x/net v0.0.0-20210805182204-aaa1db679c0d
	golang.org/x/oauth2 v0.0.0-20210622215436-a8dc77f794b6 // indirect
	golang.org/x/sys v0.0.0-20210616094352-59db8d763f22 // indirect
	golang.org/x/term v0.0.0-20210615171337-6886f2dfbf5b // indirect
	golang.org/x/time v0.0.0-20210611083556-38a9dc6acbc6 // indirect
	gomodules.xyz/jsonpatch/v2 v2.2.0 // indirect
	gopkg.in/yaml.v2 v2.4.0
	gopkg.in/yaml.v3 v3.0.0-20210107192922-496545a6307b
	k8s.io/api v0.22.2
	k8s.io/apimachinery v0.22.2
	k8s.io/client-go v0.22.0
	k8s.io/component-base v0.21.2 // indirect
	k8s.io/klog/v2 v2.9.0 // indirect
	k8s.io/utils v0.0.0-20210527160623-6fdb442a123b // indirect
	sigs.k8s.io/controller-runtime v0.9.5
)

replace (
	github.com/longhorn/longhorn-manager => github.com/replicatedhq/longhorn-manager v1.1.2-0.20210622201804-05b01947b99d
	k8s.io/api => k8s.io/api v0.20.9
	k8s.io/apiextensions-apiserver => k8s.io/apiextensions-apiserver v0.20.9
	k8s.io/apimachinery => k8s.io/apimachinery v0.20.9
	k8s.io/apiserver => k8s.io/apiserver v0.20.9
	k8s.io/cli-runtime => k8s.io/cli-runtime v0.20.9
	k8s.io/client-go => k8s.io/client-go v0.20.9
	k8s.io/cloud-provider => k8s.io/cloud-provider v0.20.9
	k8s.io/cluster-bootstrap => k8s.io/cluster-bootstrap v0.20.9
	k8s.io/code-generator => k8s.io/code-generator v0.20.9
	k8s.io/component-base => k8s.io/component-base v0.20.9
	k8s.io/cri-api => k8s.io/cri-api v0.20.9
	k8s.io/csi-translation-lib => k8s.io/csi-translation-lib v0.20.9
	k8s.io/kube-aggregator => k8s.io/kube-aggregator v0.20.9
	k8s.io/kube-controller-manager => k8s.io/kube-controller-manager v0.20.9
	k8s.io/kube-proxy => k8s.io/kube-proxy v0.20.9
	k8s.io/kube-scheduler => k8s.io/kube-scheduler v0.20.9
	k8s.io/kubectl => k8s.io/kubectl v0.20.9
	k8s.io/kubelet => k8s.io/kubelet v0.20.9
	k8s.io/legacy-cloud-providers => k8s.io/legacy-cloud-providers v0.20.9
	k8s.io/metrics => k8s.io/metrics v0.20.9
	k8s.io/sample-apiserver => k8s.io/sample-apiserver v0.20.9
	sigs.k8s.io/controller-runtime => sigs.k8s.io/controller-runtime v0.8.3
)
