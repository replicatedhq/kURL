.PHONY: image shell

image:
	docker build -f Dockerfile -t aka/e2e ..

shell:
	@docker run --rm -it \
		--volume=${PWD}/bin:/test/bin \
		--volume=${GOPATH}/src/github.com/replicatedhq/aka/dist:/dist \
		--env='GOOGLE_CREDENTIALS=$(shell cat ~/secrets/replicated-qa.json)' aka/e2e
