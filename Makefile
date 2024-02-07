NUM_BUILD_CORES := $(shell grep -c ^processor /proc/cpuinfo)

.PHONY: build
build:
	docker build \
		-f Dockerfile \
		--target runtime \
		--build-arg NUM_BUILD_CORES=$(NUM_BUILD_CORES) \
		-t ghcr.io/radusuciu/docker-openms:latest \
		-t ghcr.io/radusuciu/docker-openms:3.1.0 \
		.

.PHONY: push
push:
	docker push -a ghcr.io/radusuciu/docker-openms:3.1.0
