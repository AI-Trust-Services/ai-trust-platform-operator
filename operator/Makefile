BINARY     := aitrust-operator
SETUP_ENVTEST ?= $(shell go env GOPATH)/bin/setup-envtest
IMAGE      ?= ghcr.io/aitrust/aitrust-operator
IMAGE_TAG  ?= latest

.PHONY: build test test-integration test-e2e coverage vet fmt lint docker-build clean help

## build: compile the operator binary
build:
	CGO_ENABLED=0 go build -o $(BINARY) .

## test: run unit tests (no cluster required)
test:
	go test -v -race ./...

## test-integration: run integration tests using envtest (no live cluster required)
test-integration:
	KUBEBUILDER_ASSETS="$$( $(SETUP_ENVTEST) use -p path)" go test -v -race -tags integration -timeout 2m ./...

## test-e2e: run end-to-end tests against a live cluster
## Required env: KUBECONFIG pointing to a cluster with Platform Mesh deployed
test-e2e:
	go test -v -tags e2e -timeout 30m ./e2e/...

## coverage: run unit + integration tests and open an HTML coverage report
coverage:
	go test -tags integration -coverprofile=coverage.out -covermode=atomic ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

## vet: run go vet
vet:
	go vet ./...

## fmt: check formatting (does not modify files)
fmt:
	@gofmt -l . | tee /dev/stderr | xargs -r false

## lint: run golangci-lint (must be installed)
lint:
	golangci-lint run ./...

## docker-build: build the operator container image
docker-build:
	docker build -t $(IMAGE):$(IMAGE_TAG) .

## clean: remove build artifacts
clean:
	rm -f $(BINARY) coverage.out coverage.html

## help: list available targets
help:
	@grep -E '^## ' Makefile | sed 's/^## /  /'
