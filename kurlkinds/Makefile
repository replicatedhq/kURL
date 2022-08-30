
export GO111MODULE=on


.PHONY: all
all: test

# Run tests
.PHONY: test
test: generate fmt vet manifests
	go test ./pkg/... -coverprofile cover.out

# Run go fmt against code
.PHONY: fmt
fmt:
	go fmt ./pkg/...

# Run go vet against code
.PHONY: vet
vet:
	go vet ./pkg/...

# Get binaries
.PHONY: deps
deps: update-controller-gen update-client-gen

# Generate code
.PHONY: generate
generate: client-gen manifests

.PHONY: client-gen
client-gen:
	client-gen \
		--output-package=github.com/replicatedhq/kurl/kurlkinds/client \
		--clientset-name kurlclientset \
		--input-base github.com/replicatedhq/kurl/kurlkinds/pkg/apis \
		--input cluster/v1beta1 \
		-h ./hack/boilerplate.go.txt

.PHONY: manifests
manifests:
	controller-gen \
		rbac:roleName=manager-role webhook crd output:crd:artifacts:config=config/crds/v1beta1 paths=./pkg/apis/...
	sed -i'.orig' -e 's/type: BoolString/type: string/' config/crds/v1beta1/cluster.kurl.sh_installers.yaml
	rm config/crds/v1beta1/cluster.kurl.sh_installers.yaml.orig

.PHONY: test-crd
test-crd:
	kubectl apply -f config/crds/v1beta1/cluster.kurl.sh_installers.yaml
	kubectl apply -f config/test/cluster.kurl.sh_example.yaml
	kubectl delete crd installers.cluster.kurl.sh

.PHONY: schemas
schemas: fmt generate
	go build ${LDFLAGS} -o bin/schemagen ./schemagen
	./bin/schemagen --output-dir ./schemas

.PHONY: update-controller-gen
update-controller-gen:
	go install sigs.k8s.io/controller-tools/cmd/controller-gen@latest

.PHONY: update-client-gen
update-client-gen:
	go install k8s.io/code-generator/cmd/client-gen@latest
