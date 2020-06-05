SHELL := /bin/bash
PROJECT_NAME ?= tgweb

.PHONY: deps
deps:
	npm install

.PHONY: serve
serve:
	NODE_ENV=dev node --max-old-space-size=6144 `npm bin`/webpack-dev-server --config webpack.config.js --progress -w --color --debug --env development

