# Run this after any changes to imports
.PHONY: cache-image
cache-image:
	docker build -t kurl/util-cache -f Dockerfile.cache ../../

.PHONY: up
up: cache-image
	skaffold dev -f skaffold.yaml
