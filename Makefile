# Image URL to use all building/pushing image targets
IMG ?= controller:latest
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.28.0

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /bin/bash
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test ./... -coverprofile cover.out

##@ Build

.PHONY: build
build: manifests generate fmt vet ## Build manager binary.
	go build -o bin/manager cmd/manager/main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/manager/main.go

# If you wish built the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64 ). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build
docker-build: test ## Build docker image with the manager.
	docker build -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG}

##@ E2E Testing

.PHONY: e2e-setup
e2e-setup: ## Setup e2e test cluster
	./test/e2e/scripts/setup-cluster.sh

.PHONY: e2e-teardown
e2e-teardown: ## Teardown e2e test cluster
	./test/e2e/scripts/teardown-cluster.sh

.PHONY: e2e-test-basic
e2e-test-basic: ## Run basic e2e tests
	./test/e2e/scripts/run-test.sh basic

.PHONY: e2e-test-scaling
e2e-test-scaling: ## Run scaling e2e tests
	./test/e2e/scripts/run-test.sh scaling

.PHONY: e2e-test-deletion
e2e-test-deletion: ## Run deletion e2e tests
	./test/e2e/scripts/run-test.sh deletion

.PHONY: e2e-test-go
e2e-test-go: ## Run original Go e2e tests
	./test/e2e/scripts/run-test.sh go

.PHONY: e2e-test-all
e2e-test-all: ## Run all individual e2e tests
	./test/e2e/scripts/run-test.sh all

.PHONY: e2e-test-advanced
e2e-test-advanced: ## Run advanced e2e test scenarios
	./test/e2e/scripts/run-advanced-tests.sh all

.PHONY: e2e-test-advanced-multiple
e2e-test-advanced-multiple: ## Run advanced multiple apps test
	./test/e2e/scripts/run-advanced-tests.sh multiple

.PHONY: e2e-test-advanced-scaling
e2e-test-advanced-scaling: ## Run advanced rapid scaling test
	./test/e2e/scripts/run-advanced-tests.sh rapid-scaling

.PHONY: e2e-test-advanced-images
e2e-test-advanced-images: ## Run advanced different images test
	./test/e2e/scripts/run-advanced-tests.sh images

.PHONY: e2e-test-advanced-updates
e2e-test-advanced-updates: ## Run advanced update operations test
	./test/e2e/scripts/run-advanced-tests.sh updates

.PHONY: e2e-test-advanced-errors
e2e-test-advanced-errors: ## Run advanced error conditions test
	./test/e2e/scripts/run-advanced-tests.sh errors

.PHONY: e2e-suite
e2e-suite: ## Run complete e2e test suite with setup and teardown
	./test/e2e/scripts/run-suite.sh

.PHONY: e2e-suite-no-teardown
e2e-suite-no-teardown: ## Run e2e test suite but keep cluster for debugging
	SKIP_TEARDOWN=true ./test/e2e/scripts/run-suite.sh

.PHONY: e2e-suite-existing
e2e-suite-existing: ## Run e2e tests on existing cluster
	SKIP_SETUP=true SKIP_TEARDOWN=true ./test/e2e/scripts/run-suite.sh

.PHONY: e2e-suite-full
e2e-suite-full: ## Run complete e2e suite including advanced tests
	TEST_TYPES=all,advanced ./test/e2e/scripts/run-suite.sh

.PHONY: e2e-help
e2e-help: ## Show e2e testing help
	@echo "E2E Testing Commands:"
	@echo "====================="
	@echo "Basic workflow:"
	@echo "  make e2e-setup          # Setup test cluster"
	@echo "  make e2e-test-basic     # Run basic tests"
	@echo "  make e2e-teardown       # Cleanup cluster"
	@echo ""
	@echo "Individual tests:"
	@echo "  make e2e-test-basic     # Basic functionality"
	@echo "  make e2e-test-scaling   # Scaling operations"
	@echo "  make e2e-test-deletion  # Resource deletion"
	@echo "  make e2e-test-go        # Original Go tests"
	@echo ""
	@echo "Advanced tests:"
	@echo "  make e2e-test-advanced-multiple   # Multiple apps"
	@echo "  make e2e-test-advanced-scaling    # Rapid scaling"
	@echo "  make e2e-test-advanced-images     # Different images"
	@echo "  make e2e-test-advanced-updates    # Update operations"
	@echo "  make e2e-test-advanced-errors     # Error conditions"
	@echo ""
	@echo "Complete suites:"
	@echo "  make e2e-suite          # Full suite with setup/teardown"
	@echo "  make e2e-suite-full     # Full suite + advanced tests"
	@echo "  make e2e-suite-existing # Run on existing cluster"
	@echo ""
	@echo "Environment variables:"
	@echo "  CLUSTER_NAME=my-cluster    # Custom cluster name"
	@echo "  SKIP_SETUP=true           # Skip cluster setup"
	@echo "  SKIP_TEARDOWN=true        # Keep cluster after tests"
	@echo "  TEST_TYPES=basic,scaling   # Specific test types"

.PHONY: e2e-validate
e2e-validate: ## Validate e2e framework setup
	./test/e2e/scripts/validate-framework.sh

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN := $(shell pwd)/bin
.PHONY: create-localbin
create-localbin:
	mkdir -p "$(LOCALBIN)"

## Tool Binaries
KUSTOMIZE := $(LOCALBIN)/kustomize
CONTROLLER_GEN := $(LOCALBIN)/controller-gen
ENVTEST := $(LOCALBIN)/setup-envtest

## Tool Versions
KUSTOMIZE_VERSION ?= v5.0.1
CONTROLLER_TOOLS_VERSION ?= v0.13.0

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
.PHONY: kustomize
kustomize: create-localbin ## Download kustomize locally if necessary. If wrong version is installed, it will be removed before downloading.
	@if test -x "$(KUSTOMIZE)" && ! "$(KUSTOMIZE)" version | grep -q $(KUSTOMIZE_VERSION); then \
		echo "$(KUSTOMIZE) version is not expected $(KUSTOMIZE_VERSION). Removing it."; \
		rm -rf "$(KUSTOMIZE)"; \
	fi
	test -s "$(KUSTOMIZE)" || { curl -Ss $(KUSTOMIZE_INSTALL_SCRIPT) | bash -s -- $(subst v,,$(KUSTOMIZE_VERSION)) "$(LOCALBIN)"; }

.PHONY: controller-gen
controller-gen: create-localbin ## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
	test -s "$(CONTROLLER_GEN)" && "$(CONTROLLER_GEN)" --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN="$(LOCALBIN)" go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: create-localbin ## Download envtest-setup locally if necessary.
	test -s "$(ENVTEST)" || GOBIN="$(LOCALBIN)" go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest