
IMAGE_TAG ?= latest
FULL_IMAGE_NAME ?= docker.io/1228022817/ocserv:$(IMAGE_TAG)

.PHONY: build
build:
	@echo "Building with:"
	@echo "  CA_CN       = $(CA_CN)"
	@echo "  CA_ORG      = $(CA_ORG)"
	@echo "  SERV_DOMAIN = $(SERV_DOMAIN)"
	@echo "  SERV_ORG    = $(SERV_ORG)"
	@echo "  USER_ID     = $(USER_ID)"
	@echo "FULL_IMAGE_NAME = $(FULL_IMAGE_NAME)"
	docker buildx build . \
		-t $(FULL_IMAGE_NAME) \
		--push
