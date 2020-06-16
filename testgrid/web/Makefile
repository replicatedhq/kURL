SHELL := /bin/bash
PROJECT_NAME ?= tgweb

.PHONY: deps
deps:
	npm install

.PHONY: serve
serve:
	NODE_ENV=dev node --max-old-space-size=6144 `npm bin`/webpack-dev-server --config webpack.config.js --progress -w --color --debug --env development

.PHONY: build-staging
build-staging: deps
build-staging:
	node \
		--max_old_space_size=6144 \
		./node_modules/webpack/bin/webpack.js \
		--config webpack.config.js \
		--env staging \
		--mode production

.PHONY: build-production
build-production: deps
build-production:
	node \
		--max_old_space_size=6144 \
		./node_modules/webpack/bin/webpack.js \
		--config webpack.config.js \
		--env production \
		--mode production