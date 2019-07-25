.PHONY: image

image:
	docker build -t aka/e2e .

shell:
	@docker run --rm -it --env='GOOGLE_CREDENTIALS=$(shell cat ~/secrets/replicated-qa.json)' aka/e2e
