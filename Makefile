
# Get current timestamp in YYYY-MM-DD-HH-MM format
TIMESTAMP := $(shell date +'%Y-%m-%d-%H-%M')

IMAGE_TAG ?= $(TIMESTAMP)
FULL_IMAGE_NAME ?= docker.io/1228022817/ocserv:$(IMAGE_TAG)
ROUTE_INJECTOR_IMAGE_TAG ?= $(IMAGE_TAG)
ROUTE_INJECTOR_FULL_IMAGE_NAME ?= docker.io/1228022817/ocserv-init:$(ROUTE_INJECTOR_IMAGE_TAG)

.PHONY: build build-route-injector build-all update-values update-values-and-build help

build:
	@echo "Building ocserv image with:"
	@echo "  CA_CN       = $(CA_CN)"
	@echo "  CA_ORG      = $(CA_ORG)"
	@echo "  SERV_DOMAIN = $(SERV_DOMAIN)"
	@echo "  SERV_ORG    = $(SERV_ORG)"
	@echo "  USER_ID     = $(USER_ID)"
	@echo "FULL_IMAGE_NAME = $(FULL_IMAGE_NAME)"
	@echo "IMAGE_TAG = $(IMAGE_TAG)"
	@docker buildx build . \
		-t $(FULL_IMAGE_NAME) \
		--push

build-route-injector:
	@echo "Building route-injector image:"
	@echo "ROUTE_INJECTOR_FULL_IMAGE_NAME = $(ROUTE_INJECTOR_FULL_IMAGE_NAME)"
	@echo "ROUTE_INJECTOR_IMAGE_TAG = $(ROUTE_INJECTOR_IMAGE_TAG)"
	@docker buildx build -f Dockerfile-route-injector . \
		-t $(ROUTE_INJECTOR_FULL_IMAGE_NAME) \
		--push

build-all: build build-route-injector
	@echo "All images built successfully:"
	@echo "  OCSERV:        $(FULL_IMAGE_NAME)"
	@echo "  Route-Injector: $(ROUTE_INJECTOR_FULL_IMAGE_NAME)"

update-values:
	@echo "Updating values.yaml with new image tags:"
	@echo "  OCSERV tag: $(IMAGE_TAG)"
	@echo "  Route-Injector tag: $(ROUTE_INJECTOR_IMAGE_TAG)"
	@# Create backup
	@cp charts/ocserv/values.yaml charts/ocserv/values.yaml.bak
	@# Update ocserv image tag (first image section)
	@sed -i '0,/tag: "latest"/ s/tag: "latest"/tag: "$(IMAGE_TAG)"/' charts/ocserv/values.yaml
	@# Update route-injector daemonset repository
	@sed -i '/daemonset:/,/tag: "latest"/ s/repository: "alpine"/repository: "docker.io\/1228022817\/ocserv-init"/' charts/ocserv/values.yaml
	@# Update route-injector daemonset tag
	@sed -i '/daemonset:/,/tag: "latest"/ s/    tag: "latest"/    tag: "$(ROUTE_INJECTOR_IMAGE_TAG)"/' charts/ocserv/values.yaml
	@echo "values.yaml updated successfully (backup saved as .bak)"

update-values-and-build: update-values build-all
	@echo "Values updated and images built successfully!"

help:
	@echo "Available targets:"
	@echo "  build                    - Build ocserv image"
	@echo "  build-route-injector     - Build route-injector image"
	@echo "  build-all               - Build both images"
	@echo "  update-values           - Update values.yaml with new image tags"
	@echo "  update-values-and-build  - Update values.yaml and build all images"
	@echo "  help                   - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  IMAGE_TAG                    - Tag for ocserv image (default: YYYY-MM-DD-HH-MM)"
	@echo "  ROUTE_INJECTOR_IMAGE_TAG     - Tag for route-injector image (default: same as IMAGE_TAG)"
	@echo "  CA_CN, CA_ORG, SERV_DOMAIN, SERV_ORG, USER_ID - Build args for ocserv"
	@echo ""
	@echo "Examples:"
	@echo "  make build                          # Build with timestamp tag"
	@echo "  make build IMAGE_TAG=v1.0.0          # Build with custom tag"
	@echo "  make build-route-injector             # Build route-injector with timestamp tag"
	@echo "  make build-all IMAGE_TAG=v2.1.0         # Build both with custom tag"
	@echo "  make update-values                     # Update values.yaml with timestamp tags"
	@echo "  make update-values-and-build IMAGE_TAG=v2.0.0 # Update and build with v2.0.0"
