NUM_BUILD_CORES := $(shell grep -c ^processor /proc/cpuinfo)

.PHONY: build
build:
	docker build \
		-f Dockerfile \
		--target worker \
		--build-arg NUM_BUILD_CORES=$(NUM_BUILD_CORES) \
		--cache-to type=registry,ref=ghcr.io/radusuciu/cache-docker-openms:latest,mode=max \
		--cache-from type=registry,ref=ghcr.io/radusuciu/cache-docker-openms:latest \
		-t ghcr.io/radusuciu/docker-openms:latest \
		.

.PHONY: push
push:
	docker push ghcr.io/radusuciu/docker-openms:latest
