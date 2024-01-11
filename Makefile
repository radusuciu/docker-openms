.PHONY: build
build:
	docker build . \
		-f Dockerfile \
		--target worker \
		-t ghcr.io/radusuciu/docker-openms:latest

.PHONY: push
push:
	docker push ghcr.io/radusuciu/docker-openms:latest
