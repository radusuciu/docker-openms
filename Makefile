NUM_BUILD_CORES := $(shell grep -c ^processor /proc/cpuinfo)

.PHONY: build
build:
	docker build \
		-f Dockerfile \
		--target runtime \
		--build-arg NUM_BUILD_CORES=$(NUM_BUILD_CORES) \
		--build-arg BOOST_BUILD_CORES=4 \
		-t ghcr.io/radusuciu/docker-openms:latest \
		-t ghcr.io/radusuciu/docker-openms:3.1.0 \
		-t docker-openms:latest \
		-t docker-openms:3.1.0 \
		.

.PHONY: boost
boost:
	docker build \
		-f Dockerfile \
		--target boost-builder \
		-t docker-openms-boost \
		--build-arg NUM_BUILD_CORES=$(NUM_BUILD_CORES) \
		--build-arg BOOST_BUILD_CORES=4 \
		.

.PHONY: test
test:
	docker build \
		-f Dockerfile \
		--target test \
		--build-arg NUM_BUILD_CORES=$(NUM_BUILD_CORES) \
		--build-arg BOOST_BUILD_CORES=4 \
		-t docker-openms-test \
		.

.PHONY: push
push:
	docker push -a ghcr.io/radusuciu/docker-openms:3.1.0
