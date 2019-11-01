module github.com/replicatedhq/kurl/cmd/join

go 1.13

require (
	github.com/gin-gonic/gin v1.4.0
	github.com/googleapis/gnostic v0.3.1 // indirect
	github.com/pkg/errors v0.8.1
	github.com/soheilhy/cmux v0.1.4
	golang.org/x/net v0.0.0-20191021144547-ec77196f6094 // indirect
	golang.org/x/time v0.0.0-20191023065245-6d3f0bb11be5 // indirect
	google.golang.org/grpc v1.24.0 // indirect
	k8s.io/api v0.0.0
	k8s.io/apiextensions-apiserver v0.0.0
	k8s.io/apimachinery v0.0.0
	k8s.io/client-go v0.0.0
	k8s.io/cluster-bootstrap v0.0.0
	k8s.io/kubernetes v1.16.2
	k8s.io/utils v0.0.0-20191010214722-8d271d903fe4 // indirect
)

replace k8s.io/api => k8s.io/api v0.0.0-20190819141258-3544db3b9e44

replace k8s.io/apiextensions-apiserver => k8s.io/apiextensions-apiserver v0.0.0-20190819143637-0dbe462fe92d

replace k8s.io/apimachinery => k8s.io/apimachinery v0.0.0-20190817020851-f2f3a405f61d

replace k8s.io/apiserver => k8s.io/apiserver v0.0.0-20191016112112-5190913f932d

replace k8s.io/cli-runtime => k8s.io/cli-runtime v0.0.0-20191016114015-74ad18325ed5

replace k8s.io/client-go => k8s.io/client-go v0.0.0-20190819141724-e14f31a72a77

replace k8s.io/cloud-provider => k8s.io/cloud-provider v0.0.0-20191016115326-20453efc2458

replace k8s.io/cluster-bootstrap => k8s.io/cluster-bootstrap v0.0.0-20191016115129-c07a134afb42

replace k8s.io/code-generator => k8s.io/code-generator v0.0.0-20191004115455-8e001e5d1894

replace k8s.io/component-base => k8s.io/component-base v0.0.0-20191016111319-039242c015a9

replace k8s.io/cri-api => k8s.io/cri-api v0.0.0-20190828162817-608eb1dad4ac

replace k8s.io/csi-translation-lib => k8s.io/csi-translation-lib v0.0.0-20191016115521-756ffa5af0bd

replace k8s.io/kube-aggregator => k8s.io/kube-aggregator v0.0.0-20191016112429-9587704a8ad4

replace k8s.io/kube-controller-manager => k8s.io/kube-controller-manager v0.0.0-20191016114939-2b2b218dc1df

replace k8s.io/kube-proxy => k8s.io/kube-proxy v0.0.0-20191016114407-2e83b6f20229

replace k8s.io/kube-scheduler => k8s.io/kube-scheduler v0.0.0-20191016114748-65049c67a58b

replace k8s.io/kubectl => k8s.io/kubectl v0.0.0-20191016120415-2ed914427d51

replace k8s.io/kubelet => k8s.io/kubelet v0.0.0-20191016114556-7841ed97f1b2

replace k8s.io/legacy-cloud-providers => k8s.io/legacy-cloud-providers v0.0.0-20191016115753-cf0698c3a16b

replace k8s.io/metrics => k8s.io/metrics v0.0.0-20191016113814-3b1a734dba6e

replace k8s.io/sample-apiserver => k8s.io/sample-apiserver v0.0.0-20191016112829-06bb3c9d77c9

replace github.com/gogo/protobuf => github.com/gogo/protobuf v1.2.2-0.20190723190241-65acae22fc9d
