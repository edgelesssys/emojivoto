include ./common.mk

.PHONY: web emoji-svc voting-svc voting-update

all: build integration-tests

web:
	$(MAKE) -C emojivoto-web

emoji-svc:
	$(MAKE) -C emojivoto-emoji-svc

voting-svc:
	$(MAKE) -C emojivoto-voting-svc

voting-update:
	$(MAKE) -C emojivoto-voting-update

build: web emoji-svc voting-svc voting-update
