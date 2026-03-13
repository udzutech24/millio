SHELL := /bin/zsh

.PHONY: bundle-install testflight

bundle-install:
	bundle install

testflight:
	./scripts/release_testflight.sh
