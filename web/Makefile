.PHONY: deps build dev shell shell_composer shell_composer_dex shell_composer_linux shell_composer_prod test run

SHELL := /bin/bash
#paths within WSL start with /mnt/c/...
#docker does not recognize this fact
#this strips the first 5 characters (leaving /c/...) if the kernel releaser is Microsoft
ifeq ($(shell uname -r | tail -c 10), Microsoft)
	BUILD_DIR := $(shell pwd | cut -c 5-)
else
	BUILD_DIR := $(shell pwd)
endif

deps:
	pip install -r requirements.txt

build:
	docker build -t install-scripts -f deploy/Dockerfile.prod .

dev:
	docker build -t install-scripts-dev .

test:
	python -m pytest -v tests
	./test.sh

run:
	python main.py
