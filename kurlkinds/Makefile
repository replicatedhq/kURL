
export GO111MODULE=on

export PATH := /usr/local/kubebuilder/bin:${PATH}

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

# Get binaries
deps: update-controller-gen update-client-gen update-kubebuilder

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
	kubectl apply -f config/test/cluster.kurl.sh_example.yaml
	kubectl delete crd installers.cluster.kurl.sh


# get/update controller-gen
update-controller-gen:
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.5.0

# get/update client-gen
update-client-gen:
	go get k8s.io/code-generator/cmd/client-gen@v0.20.4

update-kubebuilder: os = $(shell go env GOOS)
update-kubebuilder: arch = $(shell go env GOARCH)
update-kubebuilder: KUBEBUILDER_VERSION = 2.3.1
update-kubebuilder:
	# download kubebuilder and extract it to tmp
	curl -fsSL https://go.kubebuilder.io/dl/${KUBEBUILDER_VERSION}/${os}/${arch} | tar -xz -C /tmp/

	sudo rm -rf /usr/local/kubebuilder
	sudo mv /tmp/kubebuilder_${KUBEBUILDER_VERSION}_${os}_${arch} /usr/local/kubebuilder
