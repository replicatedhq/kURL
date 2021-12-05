module github.com/replicatedhq/kurl

go 1.17

require (
	github.com/DataDog/datadog-go v4.8.1+incompatible
	github.com/Masterminds/sprig v2.22.0+incompatible
	github.com/apparentlymart/go-cidr v1.1.0
	github.com/aws/aws-sdk-go v1.40.18
	github.com/briandowns/spinner v1.16.0
	github.com/bugsnag/bugsnag-go/v2 v2.1.1
	github.com/chzyer/readline v0.0.0-20180603132655-2972be24d48e
	github.com/containers/image/v5 v5.17.0
	github.com/denisbrodbeck/machineid v1.0.1
	github.com/fatih/color v1.13.0
	github.com/foomo/htpasswd v0.0.0-20200116085101-e3a90e78da9c
	github.com/golang/mock v1.6.0
	github.com/gorilla/mux v1.8.0
	github.com/itchyny/gojq v0.12.4
	github.com/lib/pq v1.10.2
	github.com/mattn/go-isatty v0.0.14
	github.com/minio/minio-go v6.0.14+incompatible
	github.com/onsi/gomega v1.15.0
	github.com/pelletier/go-toml v1.9.3
	github.com/pkg/errors v0.9.1
	github.com/replicatedhq/pvmigrate v0.3.2
	github.com/replicatedhq/troubleshoot v0.22.2-0.20211201002858-27c5e5192046
	github.com/sirupsen/logrus v1.8.1
	github.com/spf13/afero v1.6.0
	github.com/spf13/cobra v1.2.1
	github.com/spf13/viper v1.8.1
	github.com/stretchr/testify v1.7.0
	github.com/vishvananda/netlink v1.1.1-0.20201029203352-d40f9887b852
	github.com/vmware-tanzu/velero v1.6.2
	go.uber.org/zap v1.19.0
	golang.org/x/crypto v0.0.0-20210513164829-c07d793c2f9a
	golang.org/x/net v0.0.0-20211005001312-d4b1ae081e3b
	gopkg.in/yaml.v2 v2.4.0
	gopkg.in/yaml.v3 v3.0.0-20210107192922-496545a6307b
	k8s.io/api v0.22.4
	k8s.io/apimachinery v0.22.4
	k8s.io/client-go v12.0.0+incompatible
	kubevirt.io/client-go v0.47.1
	sigs.k8s.io/controller-runtime v0.9.5
)

require (
	cloud.google.com/go v0.81.0 // indirect
	cloud.google.com/go/storage v1.10.0 // indirect
	github.com/BurntSushi/toml v0.4.1 // indirect
	github.com/GehirnInc/crypt v0.0.0-20190301055215-6c0105aabd46 // indirect
	github.com/Masterminds/goutils v1.1.1 // indirect
	github.com/Masterminds/semver v1.5.0 // indirect
	github.com/Microsoft/go-winio v0.5.0 // indirect
	github.com/Microsoft/hcsshim v0.8.22 // indirect
	github.com/PuerkitoBio/purell v1.1.1 // indirect
	github.com/PuerkitoBio/urlesc v0.0.0-20170810143723-de5bf2ad4578 // indirect
	github.com/StackExchange/wmi v0.0.0-20210224194228-fe8f1750fd46 // indirect
	github.com/VividCortex/ewma v1.2.0 // indirect
	github.com/acarl005/stripansi v0.0.0-20180116102854-5a71ef0e047d // indirect
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/bgentry/go-netrc v0.0.0-20140422174119-9fd32a8b3d3d // indirect
	github.com/blang/semver v3.5.1+incompatible // indirect
	github.com/bugsnag/panicwrap v1.3.2 // indirect
	github.com/c9s/goprocinfo v0.0.0-20190309065803-0b2ad9ac246b // indirect
	github.com/cespare/xxhash/v2 v2.1.1 // indirect
	github.com/containerd/cgroups v1.0.1 // indirect
	github.com/containerd/containerd v1.5.7 // indirect
	github.com/containerd/stargz-snapshotter/estargz v0.9.0 // indirect
	github.com/containers/libtrust v0.0.0-20190913040956-14b96171aa3b // indirect
	github.com/containers/ocicrypt v1.1.2 // indirect
	github.com/containers/storage v1.37.0 // indirect
	github.com/coreos/prometheus-operator v0.35.0 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/docker/distribution v2.7.1+incompatible // indirect
	github.com/docker/docker v20.10.11+incompatible // indirect
	github.com/docker/docker-credential-helpers v0.6.4 // indirect
	github.com/docker/go-connections v0.4.0 // indirect
	github.com/docker/go-metrics v0.0.1 // indirect
	github.com/docker/go-units v0.4.0 // indirect
	github.com/docker/spdystream v0.0.0-20181023171402-6480d4af844c // indirect
	github.com/emicklei/go-restful v2.10.0+incompatible // indirect
	github.com/evanphx/json-patch v4.11.0+incompatible // indirect
	github.com/felixge/httpsnoop v1.0.1 // indirect
	github.com/fsnotify/fsnotify v1.4.9 // indirect
	github.com/ghodss/yaml v1.0.0 // indirect
	github.com/go-ini/ini v1.62.0 // indirect
	github.com/go-kit/kit v0.9.0 // indirect
	github.com/go-logfmt/logfmt v0.5.0 // indirect
	github.com/go-logr/logr v0.4.0 // indirect
	github.com/go-logr/zapr v0.4.0 // indirect
	github.com/go-ole/go-ole v1.2.6 // indirect
	github.com/go-openapi/jsonpointer v0.19.5 // indirect
	github.com/go-openapi/jsonreference v0.19.5 // indirect
	github.com/go-openapi/spec v0.19.5 // indirect
	github.com/go-openapi/swag v0.19.14 // indirect
	github.com/go-redis/redis/v7 v7.2.0 // indirect
	github.com/go-sql-driver/mysql v1.5.0 // indirect
	github.com/gobwas/glob v0.2.3 // indirect
	github.com/godbus/dbus v4.1.0+incompatible // indirect
	github.com/gofrs/uuid v4.0.0+incompatible // indirect
	github.com/gogo/protobuf v1.3.2 // indirect
	github.com/golang/glog v0.0.0-20160126235308-23def4e6c14b // indirect
	github.com/golang/groupcache v0.0.0-20210331224755-41bb18bfe9da // indirect
	github.com/golang/protobuf v1.5.2 // indirect
	github.com/google/btree v1.0.1 // indirect
	github.com/google/go-cmp v0.5.6 // indirect
	github.com/google/go-intervals v0.0.2 // indirect
	github.com/google/gofuzz v1.2.0 // indirect
	github.com/google/uuid v1.3.0 // indirect
	github.com/googleapis/gax-go/v2 v2.0.5 // indirect
	github.com/googleapis/gnostic v0.5.5 // indirect
	github.com/gorilla/handlers v1.5.1 // indirect
	github.com/gorilla/websocket v1.4.2 // indirect
	github.com/gregjones/httpcache v0.0.0-20181110185634-c63ab54fda8f // indirect
	github.com/hashicorp/errwrap v1.0.0 // indirect
	github.com/hashicorp/go-cleanhttp v0.5.2 // indirect
	github.com/hashicorp/go-getter v1.5.9 // indirect
	github.com/hashicorp/go-hclog v0.0.0-20180709165350-ff2cf002a8dd // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hashicorp/go-plugin v0.0.0-20190610192547-a1bc61569a26 // indirect
	github.com/hashicorp/go-safetemp v1.0.0 // indirect
	github.com/hashicorp/go-version v1.3.0 // indirect
	github.com/hashicorp/golang-lru v0.5.4 // indirect
	github.com/hashicorp/hcl v1.0.0 // indirect
	github.com/hashicorp/yamux v0.0.0-20180604194846-3520598351bb // indirect
	github.com/huandu/xstrings v1.3.2 // indirect
	github.com/imdario/mergo v0.3.12 // indirect
	github.com/inconshreveable/mousetrap v1.0.0 // indirect
	github.com/itchyny/timefmt-go v0.1.3 // indirect
	github.com/jmespath/go-jmespath v0.4.0 // indirect
	github.com/josharian/intern v1.0.0 // indirect
	github.com/json-iterator/go v1.1.12 // indirect
	github.com/jstemmer/go-junit-report v0.9.1 // indirect
	github.com/k8snetworkplumbingwg/network-attachment-definition-client v0.0.0-20191119172530-79f836b90111 // indirect
	github.com/kardianos/osext v0.0.0-20190222173326-2bc1f35cddc0 // indirect
	github.com/klauspost/compress v1.13.6 // indirect
	github.com/klauspost/pgzip v1.2.5 // indirect
	github.com/kubernetes-csi/external-snapshotter/v2 v2.1.1 // indirect
	github.com/liggitt/tabwriter v0.0.0-20181228230101-89fcab3d43de // indirect
	github.com/longhorn/go-iscsi-helper v0.0.0-20210330030558-49a327fb024e // indirect
	github.com/magiconair/properties v1.8.5 // indirect
	github.com/mailru/easyjson v0.7.6 // indirect
	github.com/mattn/go-colorable v0.1.9 // indirect
	github.com/mattn/go-runewidth v0.0.13 // indirect
	github.com/mattn/go-shellwords v1.0.12 // indirect
	github.com/matttproud/golang_protobuf_extensions v1.0.2-0.20181231171920-c182affec369 // indirect
	github.com/miekg/pkcs11 v1.0.3 // indirect
	github.com/mistifyio/go-zfs v2.1.2-0.20190413222219-f784269be439+incompatible // indirect
	github.com/mitchellh/copystructure v1.2.0 // indirect
	github.com/mitchellh/go-homedir v1.1.0 // indirect
	github.com/mitchellh/go-testing-interface v1.0.0 // indirect
	github.com/mitchellh/mapstructure v1.4.1 // indirect
	github.com/mitchellh/reflectwalk v1.0.2 // indirect
	github.com/moby/sys/mountinfo v0.4.1 // indirect
	github.com/modern-go/concurrent v0.0.0-20180306012644-bacd9c7ef1dd // indirect
	github.com/modern-go/reflect2 v1.0.2 // indirect
	github.com/mtrmac/gpgme v0.1.2 // indirect
	github.com/oklog/run v1.0.0 // indirect
	github.com/opencontainers/go-digest v1.0.0 // indirect
	github.com/opencontainers/image-spec v1.0.2-0.20210819154149-5ad6f50d6283 // indirect
	github.com/opencontainers/runc v1.0.2 // indirect
	github.com/opencontainers/runtime-spec v1.0.3-0.20210326190908-1c3f411f0417 // indirect
	github.com/opencontainers/selinux v1.9.1 // indirect
	github.com/openshift/api v0.0.0 // indirect
	github.com/openshift/client-go v0.0.0 // indirect
	github.com/openshift/custom-resource-status v0.0.0-20200602122900-c002fd1547ca // indirect
	github.com/ostreedev/ostree-go v0.0.0-20190702140239-759a8c1ac913 // indirect
	github.com/pborman/uuid v1.2.0 // indirect
	github.com/peterbourgon/diskv v2.0.1+incompatible // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/prometheus/client_golang v1.11.0 // indirect
	github.com/prometheus/client_model v0.2.0 // indirect
	github.com/prometheus/common v0.29.0 // indirect
	github.com/prometheus/procfs v0.6.0 // indirect
	github.com/rivo/uniseg v0.2.0 // indirect
	github.com/satori/go.uuid v1.2.0 // indirect
	github.com/segmentio/ksuid v1.0.4 // indirect
	github.com/shirou/gopsutil v3.21.10+incompatible // indirect
	github.com/spf13/cast v1.3.1 // indirect
	github.com/spf13/jwalterweatherman v1.1.0 // indirect
	github.com/spf13/pflag v1.0.5 // indirect
	github.com/stefanberger/go-pkcs11uri v0.0.0-20201008174630-78d3cae3a980 // indirect
	github.com/subosito/gotenv v1.2.0 // indirect
	github.com/syndtr/gocapability v0.0.0-20200815063812-42c35b437635 // indirect
	github.com/tchap/go-patricia v2.3.0+incompatible // indirect
	github.com/tklauser/go-sysconf v0.3.9 // indirect
	github.com/tklauser/numcpus v0.3.0 // indirect
	github.com/ulikunitz/xz v0.5.10 // indirect
	github.com/vbatts/tar-split v0.11.2 // indirect
	github.com/vbauerster/mpb/v7 v7.1.5 // indirect
	github.com/vishvananda/netns v0.0.0-20200728191858-db3c7e526aae // indirect
	go.etcd.io/bbolt v1.3.6 // indirect
	go.mozilla.org/pkcs7 v0.0.0-20200128120323-432b2356ecb1 // indirect
	go.opencensus.io v0.23.0 // indirect
	go.uber.org/atomic v1.7.0 // indirect
	go.uber.org/multierr v1.6.0 // indirect
	golang.org/x/lint v0.0.0-20210508222113-6edffad5e616 // indirect
	golang.org/x/mod v0.4.2 // indirect
	golang.org/x/oauth2 v0.0.0-20210622215436-a8dc77f794b6 // indirect
	golang.org/x/sync v0.0.0-20210220032951-036812b2e83c // indirect
	golang.org/x/sys v0.0.0-20211004093028-2c5d950f24ef // indirect
	golang.org/x/term v0.0.0-20210615171337-6886f2dfbf5b // indirect
	golang.org/x/text v0.3.7 // indirect
	golang.org/x/time v0.0.0-20210723032227-1f47c861a9ac // indirect
	golang.org/x/tools v0.1.5 // indirect
	golang.org/x/xerrors v0.0.0-20200804184101-5ec99f83aff1 // indirect
	gomodules.xyz/jsonpatch/v2 v2.2.0 // indirect
	google.golang.org/api v0.44.0 // indirect
	google.golang.org/appengine v1.6.7 // indirect
	google.golang.org/genproto v0.0.0-20211005153810-c76a74d43a8e // indirect
	google.golang.org/grpc v1.41.0 // indirect
	google.golang.org/protobuf v1.27.1 // indirect
	gopkg.in/check.v1 v1.0.0-20201130134442-10cb98267c6c // indirect
	gopkg.in/inf.v0 v0.9.1 // indirect
	gopkg.in/ini.v1 v1.62.0 // indirect
	gopkg.in/square/go-jose.v2 v2.5.1 // indirect
	k8s.io/apiextensions-apiserver v0.22.2 // indirect
	k8s.io/apiserver v0.22.4 // indirect
	k8s.io/cli-runtime v0.21.5 // indirect
	k8s.io/component-base v0.21.3 // indirect
	k8s.io/klog/v2 v2.9.0 // indirect
	k8s.io/kube-openapi v0.0.0-20211109043538-20434351676c // indirect
	k8s.io/utils v0.0.0-20210819203725-bdf08cb9a70a // indirect
	kubevirt.io/containerized-data-importer v1.36.0 // indirect
	kubevirt.io/controller-lifecycle-operator-sdk v0.2.0 // indirect
	sigs.k8s.io/kustomize v2.0.3+incompatible // indirect
	sigs.k8s.io/structured-merge-diff/v4 v4.1.2 // indirect
	sigs.k8s.io/yaml v1.2.0 // indirect
)

replace (
	// from github.com/replicatedhq/troubleshoot and github.com/kubevirt/client-go
	github.com/StackExchange/wmi => github.com/yusufpapurcu/wmi v1.2.2
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
