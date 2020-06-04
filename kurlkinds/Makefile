
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

controller-gen: get-controller-gen
	$(CONTROLLER_GEN) \
		object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/

client-gen: get-client-gen
	$(CLIENT_GEN) \
		--output-package=github.com/replicatedhq/kurl/kurlkinds/client \
		--clientset-name kurlclientset \
		--input-base github.com/replicatedhq/kurl/kurlkinds/pkg/apis \
		--input cluster/v1beta1 \
		-h ./hack/boilerplate.go.txt

manifests:
	$(CONTROLLER_GEN) \
		rbac:roleName=manager-role webhook crd output:crd:artifacts:config=config/crds/v1beta1 paths=./pkg/apis/...

test-crd:
	kubectl apply -f config/crds/v1beta1/cluster.kurl.sh_installers.yaml
	kubectl apply -f config/test/cluster.kurl.sh_example.yaml
	kubectl delete crd installers.cluster.kurl.sh

.PHONY: get-contoller-gen
get-controller-gen:
ifeq (, $(shell which controller-gen))
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.8
CONTROLLER_GEN=$(shell go env GOPATH)/bin/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

.PHONY: get-client-gen
get-client-gen:
ifeq (, $(shell which client-gen))
	go get k8s.io/code-generator/cmd/client-gen@kubernetes-1.18.0
CLIENT_GEN=$(shell go env GOPATH)/bin/client-gen
else
CLIENT_GEN=$(shell which client-gen)
endif