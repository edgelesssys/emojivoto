include ./common.mk

.PHONY: web emoji-svc voting-svc

all: build integration-tests

web:
	$(MAKE) -C emojivoto-web

emoji-svc:
	$(MAKE) -C emojivoto-emoji-svc

voting-svc:
	$(MAKE) -C emojivoto-voting-svc

build: web emoji-svc voting-svc

patch:
	patch -ruN -p 1 -d emojivoto-voting-svc < voting.patch
	$(MAKE) -C emojivoto-voting-svc
