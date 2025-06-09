#!/bin/bash

# E2E Test Cluster Setup Script
# This script creates a kind cluster for e2e testing

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"vertikal-e2e"}
KIND_CONFIG=${KIND_CONFIG:-"test/e2e/kind-config.yaml"}
CONTROLLER_IMAGE=${CONTROLLER_IMAGE:-"controller:latest"}
KIND_VERSION=${KIND_VERSION:-""}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-""}

check_dependencies() {
    log "Checking dependencies..."
    
    check_command "kind"
    check_command "kubectl"
    check_command "docker"
    check_command "make"
    
    # Check if docker is running
    if ! docker info &> /dev/null; then
        error "Docker is not running. Please start Docker first."
    fi
    
    log "All dependencies are available"
}

detect_and_setup_node_provider() {
    log "Detecting and setting up container runtime for kind..."
    
    # Let kind auto-detect the provider by not specifying any flags
    # kind automatically chooses between docker and podman based on availability
    
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        log "Docker detected and running - kind will use Docker"
        export KIND_EXPERIMENTAL_PROVIDER=""  # Use default detection
    elif command -v podman &> /dev/null; then
        log "Podman detected - kind will use Podman"
        export KIND_EXPERIMENTAL_PROVIDER="podman"
    else
        error "No supported container runtime found (docker or podman)"
    fi
    
    # Display kind version and provider info
    kind version
}

create_cluster() {
    log "Creating kind cluster: $CLUSTER_NAME"
    
    # Check if cluster already exists
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        warn "Cluster $CLUSTER_NAME already exists. Deleting it first..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    
    # Build kind create command
    local kind_cmd="kind create cluster --name $CLUSTER_NAME"
    
    # Add config if available
    if [[ -f "$KIND_CONFIG" ]]; then
        log "Using kind config: $KIND_CONFIG"
        kind_cmd="$kind_cmd --config $KIND_CONFIG"
    else
        warn "Kind config file not found: $KIND_CONFIG. Creating cluster with default configuration."
    fi
    
    # Add Kubernetes version if specified
    if [[ -n "$KUBERNETES_VERSION" ]]; then
        log "Using Kubernetes version: $KUBERNETES_VERSION"
        kind_cmd="$kind_cmd --image kindest/node:$KUBERNETES_VERSION"
    fi
    
    # Create the cluster
    log "Executing: $kind_cmd"
    eval "$kind_cmd"
    
    # Set kubeconfig context
    kubectl cluster-info --context "kind-$CLUSTER_NAME"
    
    log "Cluster $CLUSTER_NAME created successfully"
}

wait_for_cluster() {
    log "Waiting for cluster to be ready..."
    
    # Wait for all nodes to be ready
    wait_for_resource "nodes" "Ready" "300s"
    
    # Wait for system pods to be ready
    wait_for_resource "pods" "Ready" "300s" "kube-system"
    
    log "Cluster is ready"
}

build_and_load_image() {
    log "Building and loading controller image..."
    
    # Build the controller image
    log "Building image: $CONTROLLER_IMAGE"
    make docker-build IMG="$CONTROLLER_IMAGE"
    
    # Load the image into kind cluster
    log "Loading image into kind cluster..."
    kind load docker-image "$CONTROLLER_IMAGE" --name "$CLUSTER_NAME"
    
    log "Controller image loaded successfully"
}

install_crds() {
    log "Installing CRDs..."
    
    make install
    
    # Verify CRDs are installed
    kubectl get crd vertikalapps.vertikal.werner.io
    
    log "CRDs installed successfully"
}

deploy_controller() {
    log "Deploying controller..."
    
    make deploy IMG="$CONTROLLER_IMAGE"
    
    # Wait for controller deployment to be ready
    log "Waiting for controller to be ready..."
    wait_for_resource "deployment/vertikal-controller-manager" "available" "300s" "vertikal-system"
    
    # Verify controller pods are running
    kubectl get pods -n vertikal-system
    
    log "Controller deployed successfully"
}

main() {
    log "Starting e2e cluster setup..."
    print_environment
    
    check_dependencies
    detect_and_setup_node_provider
    create_cluster
    wait_for_cluster
    build_and_load_image
    install_crds
    deploy_controller
    
    log "E2E cluster setup completed successfully!"
    log "Cluster name: $CLUSTER_NAME"
    log "Use 'kubectl --context kind-$CLUSTER_NAME' to interact with the cluster"
    
    # Final health check
    check_cluster_health "$CLUSTER_NAME"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  CLUSTER_NAME         Name of the kind cluster (default: vertikal-e2e)"
        echo "  KIND_CONFIG          Path to kind config file (default: test/e2e/kind-config.yaml)"
        echo "  CONTROLLER_IMAGE     Controller image tag (default: controller:latest)"
        echo "  KUBERNETES_VERSION   Kubernetes version for kind (optional, e.g., v1.28.0)"
        echo "  KIND_VERSION         Kind version to use (optional)"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown argument: $1. Use --help for usage information."
        ;;
esac
