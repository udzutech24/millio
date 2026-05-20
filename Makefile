SHELL := /bin/zsh

.PHONY: bundle-install test testflight

bundle-install:
	bundle install

test:
	./scripts/coverage_gate.sh

testflight:
	./scripts/release_testflight.sh
