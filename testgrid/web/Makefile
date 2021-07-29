SHELL := /bin/bash
PROJECT_NAME ?= tgweb

.PHONY: deps
deps:
	npm install

depcheck:
	# npm install depcheck -g
	depcheck . --specials=webpack,babel,bin,eslint

.PHONY: serve
serve:
	npm start

.PHONY: build-staging
build-staging: deps
build-staging:
	node \
		--max_old_space_size=6144 \
		./node_modules/webpack/bin/webpack.js \
		--config webpack.config.js \
		--env staging \
		--mode production
	cp _redirects dist-staging

.PHONY: build-production
build-production: deps
build-production:
	node \
		--max_old_space_size=6144 \
		./node_modules/webpack/bin/webpack.js \
		--config webpack.config.js \
		--env production \
		--mode production
	cp _redirects dist-prod