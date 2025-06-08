#!/bin/bash

# E2E Test Suite Runner
# This script runs the complete e2e test suite with setup and teardown

set -euo pipefail

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"vertikal-e2e"}
SKIP_SETUP=${SKIP_SETUP:-"false"}
SKIP_TEARDOWN=${SKIP_TEARDOWN:-"false"}
TEST_TYPES=${TEST_TYPES:-"all"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

setup_cluster() {
    if [[ "$SKIP_SETUP" == "true" ]]; then
        log "Skipping cluster setup (SKIP_SETUP=true)"
        return
    fi
    
    log "Setting up e2e cluster..."
    "$SCRIPT_DIR/setup-cluster.sh"
}

teardown_cluster() {
    if [[ "$SKIP_TEARDOWN" == "true" ]]; then
        log "Skipping cluster teardown (SKIP_TEARDOWN=true)"
        return
    fi
    
    log "Tearing down e2e cluster..."
    "$SCRIPT_DIR/teardown-cluster.sh"
}

run_tests() {
    log "Running e2e tests..."
    
    # Convert comma-separated test types to array
    IFS=',' read -ra TESTS <<< "$TEST_TYPES"
    
    for test_type in "${TESTS[@]}"; do
        test_type=$(echo "$test_type" | xargs) # trim whitespace
        
        info "Running test type: $test_type"
        
        case "$test_type" in
            "advanced")
                "$SCRIPT_DIR/run-advanced-tests.sh" "all"
                ;;
            "advanced-"*)
                # Extract the specific advanced test type
                local advanced_type="${test_type#advanced-}"
                "$SCRIPT_DIR/run-advanced-tests.sh" "$advanced_type"
                ;;
            *)
                "$SCRIPT_DIR/run-test.sh" "$test_type"
                ;;
        esac
    done
}

print_summary() {
    log "E2E Test Suite Summary"
    echo "=========================="
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Tests Run: $TEST_TYPES"
    echo "Setup Skipped: $SKIP_SETUP"
    echo "Teardown Skipped: $SKIP_TEARDOWN"
    echo "=========================="
}

main() {
    log "Starting e2e test suite..."
    
    # Setup cleanup on exit if not skipping teardown
    if [[ "$SKIP_TEARDOWN" != "true" ]]; then
        trap teardown_cluster EXIT
    fi
    
    setup_cluster
    run_tests
    print_summary
    
    log "E2E test suite completed successfully!"
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
        echo "  CLUSTER_NAME      Name of the kind cluster (default: vertikal-e2e)"
        echo "  SKIP_SETUP        Skip cluster setup (default: false)"
        echo "  SKIP_TEARDOWN     Skip cluster teardown (default: false)"
        echo "  TEST_TYPES        Comma-separated test types to run (default: all)"
        echo "                    Available: basic,scaling,deletion,go,all,advanced"
        echo "                    Advanced: advanced-multiple,advanced-scaling,advanced-images,"
        echo "                             advanced-updates,advanced-errors,advanced-cleanup"
        echo ""
        echo "Examples:"
        echo "  $0                           # Run all tests with full setup/teardown"
        echo "  SKIP_SETUP=true $0           # Run tests on existing cluster"
        echo "  SKIP_TEARDOWN=true $0        # Keep cluster after tests"
        echo "  TEST_TYPES=basic,scaling $0  # Run only specific tests"
        echo "  TEST_TYPES=all,advanced $0   # Run all tests including advanced"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown argument: $1. Use --help for usage information."
        ;;
esac
