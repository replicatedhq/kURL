
export GO111MODULE=on

# Image URL to use all building/pushing image targets
IMG ?= controller:latest

all: test manager

# Run tests
test: generate fmt vet manifests
	go test ./pkg/... ./cmd/... -coverprofile cover.out

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager github.com/replicatedhq/kurl/kurlkinds/cmd/manager

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet
	go run ./cmd/manager/main.go

# Run go fmt against code
fmt:
	go fmt ./pkg/... ./cmd/...

# Run go vet against code
vet:
	go vet ./pkg/... ./cmd/...

# Generate code
generate: controller-gen client-gen manifests

controller-gen:
	controller-gen \
		object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/

client-gen:
	client-gen \
		--output-package=github.com/replicatedhq/kurl/kurlkinds/client \
		--clientset-name kurlclientset \
		--input-base github.com/replicatedhq/kurl/kurlkinds/pkg/apis \
		--input cluster/v1beta1 \
		-h ./hack/boilerplate.go.txt

manifests:
	controller-gen \
		rbac:roleName=manager-role webhook crd output:crd:artifacts:config=config/crds/v1beta1 paths=./pkg/apis/...

test-crd:
	kubectl apply -f config/crds/v1beta1/cluster.kurl.sh_installers.yaml
	cp config/template/cluster.kurl.sh_template.yaml config/test/temp.yaml
	cp ../scripts/common/yaml.sh config/test/temp.sh
	cat config/test/test_installer_crd.sh >> config/test/temp.sh
	bash config/test/temp.sh config/test/temp.yaml
	kubectl apply -f config/test/temp.yaml
	rm config/test/temp.sh
	rm config/test/temp.yaml
	#kubectl delete crd installers.cluster.kurl.sh
