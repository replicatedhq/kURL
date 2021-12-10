module github.com/replicatedhq/kurl

go 1.17

require (
	github.com/DataDog/datadog-go v4.8.1+incompatible
	github.com/Masterminds/goutils v1.1.1 // indirect
	github.com/Masterminds/semver v1.5.0 // indirect
	github.com/Masterminds/sprig v2.22.0+incompatible
	github.com/apparentlymart/go-cidr v1.1.0
	github.com/aws/aws-sdk-go v1.40.18
	github.com/briandowns/spinner v1.16.0
	github.com/bugsnag/bugsnag-go/v2 v2.1.1
	github.com/c9s/goprocinfo v0.0.0-20190309065803-0b2ad9ac246b // indirect
	github.com/chzyer/readline v0.0.0-20180603132655-2972be24d48e
	github.com/containers/image/v5 v5.17.0
	github.com/denisbrodbeck/machineid v1.0.1
	github.com/fatih/color v1.13.0
	github.com/foomo/htpasswd v0.0.0-20200116085101-e3a90e78da9c
	github.com/go-ini/ini v1.62.0 // indirect
	github.com/go-logr/zapr v0.4.0 // indirect
	github.com/go-openapi/spec v0.19.5 // indirect
	github.com/golang/mock v1.6.0
	github.com/gorilla/mux v1.8.0
	github.com/huandu/xstrings v1.3.2 // indirect
	github.com/itchyny/gojq v0.12.4
	github.com/lib/pq v1.10.4
	github.com/mattn/go-isatty v0.0.14
	github.com/minio/minio-go v6.0.14+incompatible
	github.com/mitchellh/copystructure v1.2.0 // indirect
	github.com/onsi/gomega v1.15.0
	github.com/pelletier/go-toml v1.9.4
	github.com/pkg/errors v0.9.1
	github.com/prometheus/common v0.29.0 // indirect
	github.com/replicatedhq/pvmigrate v0.4.1
	github.com/replicatedhq/troubleshoot v0.23.1-0.20211210033336-6419bb8bb7ff
	github.com/replicatedhq/yaml/v3 v3.0.0-beta5-replicatedhq
	github.com/sirupsen/logrus v1.8.1
	github.com/spf13/afero v1.6.0
	github.com/spf13/cobra v1.2.1
	github.com/spf13/viper v1.9.0
	github.com/stretchr/testify v1.7.0
	github.com/vishvananda/netlink v1.1.1-0.20201029203352-d40f9887b852
	github.com/vmware-tanzu/velero v1.6.2
	go.uber.org/zap v1.19.0
	golang.org/x/crypto v0.0.0-20210817164053-32db794688a5
	golang.org/x/lint v0.0.0-20210508222113-6edffad5e616
	golang.org/x/net v0.0.0-20211005001312-d4b1ae081e3b
	golang.org/x/term v0.0.0-20210615171337-6886f2dfbf5b // indirect
	gomodules.xyz/jsonpatch/v2 v2.2.0 // indirect
	gopkg.in/check.v1 v1.0.0-20201130134442-10cb98267c6c // indirect
	gopkg.in/yaml.v2 v2.4.0
	gopkg.in/yaml.v3 v3.0.0-20210107192922-496545a6307b
	k8s.io/api v0.22.4
	k8s.io/apimachinery v0.22.4
	k8s.io/client-go v12.0.0+incompatible
	k8s.io/code-generator v0.22.4
	k8s.io/component-base v0.21.3 // indirect
	kubevirt.io/client-go v0.47.1
	sigs.k8s.io/controller-runtime v0.10.3
	sigs.k8s.io/controller-tools v0.7.0
)

replace (
	// from github.com/replicatedhq/troubleshoot and github.com/kubevirt/client-go
	github.com/go-ole/go-ole => github.com/go-ole/go-ole v1.2.6 // needed for arm builds
	github.com/onsi/ginkgo => github.com/onsi/ginkgo v1.12.1
	github.com/onsi/gomega => github.com/onsi/gomega v1.10.1
	github.com/openshift/api => github.com/openshift/api v0.0.0-20210105115604-44119421ec6b
	github.com/openshift/client-go => github.com/openshift/client-go v0.0.0-20210112165513-ebc401615f47
	github.com/operator-framework/operator-lifecycle-manager => github.com/operator-framework/operator-lifecycle-manager v0.0.0-20190128024246-5eb7ae5bdb7a
	gopkg.in/yaml.v2 => gopkg.in/yaml.v2 v2.2.4

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
	k8s.io/klog => k8s.io/klog v0.4.0
	k8s.io/kube-aggregator => k8s.io/kube-aggregator v0.20.9
	k8s.io/kube-controller-manager => k8s.io/kube-controller-manager v0.20.9
	k8s.io/kube-openapi => k8s.io/kube-openapi v0.0.0-20210113233702-8566a335510f
	k8s.io/kube-proxy => k8s.io/kube-proxy v0.20.9
	k8s.io/kube-scheduler => k8s.io/kube-scheduler v0.20.9
	k8s.io/kubectl => k8s.io/kubectl v0.20.9
	k8s.io/kubelet => k8s.io/kubelet v0.20.9
	k8s.io/legacy-cloud-providers => k8s.io/legacy-cloud-providers v0.20.9
	k8s.io/metrics => k8s.io/metrics v0.20.9
	k8s.io/node-api => k8s.io/node-api v0.20.9
	k8s.io/sample-apiserver => k8s.io/sample-apiserver v0.20.9
	k8s.io/sample-cli-plugin => k8s.io/sample-cli-plugin v0.20.9
	k8s.io/sample-controller => k8s.io/sample-controller v0.20.9
	kubevirt.io/containerized-data-importer => kubevirt.io/containerized-data-importer v1.36.0
	sigs.k8s.io/controller-runtime => sigs.k8s.io/controller-runtime v0.8.3
	sigs.k8s.io/structured-merge-diff => sigs.k8s.io/structured-merge-diff v0.0.0-20190302045857-e85c7b244fd2
)
