#!/bin/bash

# E2E Test Cluster Teardown Script
# This script cleans up the kind cluster used for e2e testing

set -euo pipefail

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"vertikal-e2e"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

check_dependencies() {
    log "Checking dependencies..."
    
    # Check if kind is installed
    if ! command -v kind &> /dev/null; then
        error "kind is not installed. Please install kind first."
    fi
    
    log "Dependencies available"
}

delete_cluster() {
    log "Checking if cluster $CLUSTER_NAME exists..."
    
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        log "Deleting kind cluster: $CLUSTER_NAME"
        kind delete cluster --name "$CLUSTER_NAME"
        log "Cluster $CLUSTER_NAME deleted successfully"
    else
        warn "Cluster $CLUSTER_NAME does not exist or is already deleted"
    fi
}

cleanup_docker_images() {
    log "Cleaning up Docker images..."
    
    # Remove controller images that might be left over
    if docker images | grep -q "controller.*latest"; then
        warn "Found controller images, you may want to clean them up manually:"
        docker images | grep "controller.*latest" || true
    fi
}

main() {
    log "Starting e2e cluster teardown..."
    
    check_dependencies
    delete_cluster
    cleanup_docker_images
    
    log "E2E cluster teardown completed successfully!"
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
        echo "  CLUSTER_NAME   Name of the kind cluster to delete (default: vertikal-e2e)"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown argument: $1. Use --help for usage information."
        ;;
esac
