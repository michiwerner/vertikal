#!/bin/bash

# Individual E2E Test Runner
# This script runs a specific e2e test scenario

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"vertikal-e2e"}
TEST_NAMESPACE=${TEST_NAMESPACE:-"vertikal-test"}
TEST_NAME=${TEST_NAME:-""}

check_dependencies() {
    log "Checking dependencies..."
    
    check_command "kubectl"
    check_command "go"
    
    log "Dependencies available"
}

check_cluster() {
    log "Checking if cluster is available..."
    
    # Check if cluster exists
    if ! kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        error "Cluster $CLUSTER_NAME does not exist. Run setup-cluster.sh first."
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info --context "kind-$CLUSTER_NAME" &> /dev/null; then
        error "Cannot access cluster $CLUSTER_NAME. Please check your kubeconfig."
    fi
    
    # Check if controller is running
    if ! kubectl get deployment vertikal-controller-manager -n vertikal-system --context "kind-$CLUSTER_NAME" &> /dev/null; then
        error "Controller is not deployed. Run setup-cluster.sh first."
    fi
    
    log "Cluster is ready for testing"
}

create_test_namespace() {
    log "Creating test namespace: $TEST_NAMESPACE"
    
    # Set context for the cluster
    kubectl config use-context "kind-$CLUSTER_NAME"
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    log "Test namespace ready"
}

cleanup_test_namespace() {
    cleanup_namespace "$TEST_NAMESPACE"
}

run_basic_vertikalapp_test() {
    log "Running basic VertikalApp test..."
    
    # Apply test VertikalApp
    local manifest
    manifest=$(create_vertikalapp_manifest "test-app" "$TEST_NAMESPACE" "2")
    apply_manifest "$manifest"

    # Wait for deployment to be created
    log "Waiting for deployment to be created..."
    wait_for_resource "deployment/test-app" "available" "120s" "$TEST_NAMESPACE"
    
    # Verify deployment has correct replicas
    verify_resource_field "deployment" "test-app" ".spec.replicas" "2" "$TEST_NAMESPACE"
    
    # Verify service was created
    kubectl get service test-app -n "$TEST_NAMESPACE"
    
    log "Basic VertikalApp test passed"
}

run_scaling_test() {
    log "Running scaling test..."
    
    # Apply initial VertikalApp
    cat <<EOF | kubectl apply -f -
apiVersion: vertikal.naptime.dev/v1alpha1
kind: VertikalApp
metadata:
  name: test-scale-app
  namespace: $TEST_NAMESPACE
spec:
  size: 1
  image: nginx:latest
  port: 80
EOF

    # Wait for initial deployment
    kubectl wait --for=condition=available --timeout=120s deployment/test-scale-app -n "$TEST_NAMESPACE"
    
    # Scale up
    log "Scaling up to 3 replicas..."
    cat <<EOF | kubectl apply -f -
apiVersion: vertikal.naptime.dev/v1alpha1
kind: VertikalApp
metadata:
  name: test-scale-app
  namespace: $TEST_NAMESPACE
spec:
  size: 3
  image: nginx:latest
  port: 80
EOF

    # Wait for scaling to complete
    kubectl wait --for=condition=available --timeout=120s deployment/test-scale-app -n "$TEST_NAMESPACE"
    
    # Wait for all pods to be ready
    sleep 10
    kubectl wait --for=condition=Ready --timeout=120s pods -l app=test-scale-app -n "$TEST_NAMESPACE"
    
    # Verify scaling
    local replicas=$(kubectl get deployment test-scale-app -n "$TEST_NAMESPACE" -o jsonpath='{.spec.replicas}')
    if [[ "$replicas" != "3" ]]; then
        error "Expected 3 replicas after scaling, got $replicas"
    fi
    
    local ready_replicas=$(kubectl get deployment test-scale-app -n "$TEST_NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    if [[ "$ready_replicas" != "3" ]]; then
        error "Expected 3 ready replicas after scaling, got $ready_replicas"
    fi
    
    log "Scaling test passed"
}

run_deletion_test() {
    log "Running deletion test..."
    
    # Apply VertikalApp
    cat <<EOF | kubectl apply -f -
apiVersion: vertikal.naptime.dev/v1alpha1
kind: VertikalApp
metadata:
  name: test-delete-app
  namespace: $TEST_NAMESPACE
spec:
  size: 2
  image: nginx:latest
  port: 80
EOF

    # Wait for deployment to be created
    kubectl wait --for=condition=available --timeout=120s deployment/test-delete-app -n "$TEST_NAMESPACE"
    
    # Delete the VertikalApp
    kubectl delete vertikalapp test-delete-app -n "$TEST_NAMESPACE"
    
    # Wait for deployment to be deleted
    log "Waiting for deployment to be deleted..."
    while kubectl get deployment test-delete-app -n "$TEST_NAMESPACE" &> /dev/null; do
        info "Waiting for deployment to be deleted..."
        sleep 2
    done
    
    # Wait for service to be deleted
    while kubectl get service test-delete-app -n "$TEST_NAMESPACE" &> /dev/null; do
        info "Waiting for service to be deleted..."
        sleep 2
    done
    
    log "Deletion test passed"
}

run_go_test() {
    log "Running Go e2e tests..."
    
    # Set the kubeconfig for the test
    export KUBECONFIG="$HOME/.kube/config"
    
    # Run the specific test or all tests
    if [[ -n "$TEST_NAME" ]]; then
        go test ./test/e2e -v -run "$TEST_NAME"
    else
        go test ./test/e2e -v
    fi
    
    log "Go e2e tests completed"
}

main() {
    local test_type="${1:-basic}"
    
    log "Starting e2e test: $test_type"
    
    check_dependencies
    check_cluster
    create_test_namespace
    
    # Run cleanup on exit
    trap cleanup_test_namespace EXIT
    
    case "$test_type" in
        "basic")
            run_basic_vertikalapp_test
            ;;
        "scaling")
            run_scaling_test
            ;;
        "deletion")
            run_deletion_test
            ;;
        "go")
            run_go_test
            ;;
        "all")
            run_basic_vertikalapp_test
            run_scaling_test
            run_deletion_test
            ;;
        *)
            error "Unknown test type: $test_type. Available: basic, scaling, deletion, go, all"
            ;;
    esac
    
    log "E2E test '$test_type' completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [test-type] [options]"
        echo ""
        echo "Test types:"
        echo "  basic      Test basic VertikalApp creation and deployment"
        echo "  scaling    Test scaling up and down of VertikalApp"
        echo "  deletion   Test deletion of VertikalApp and cleanup"
        echo "  go         Run the original Go e2e tests"
        echo "  all        Run all shell-based tests (default: basic)"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  CLUSTER_NAME     Name of the kind cluster (default: vertikal-e2e)"
        echo "  TEST_NAMESPACE   Namespace for test resources (default: vertikal-test)"
        echo "  TEST_NAME        Specific test name for Go tests (optional)"
        exit 0
        ;;
    "")
        main "basic"
        ;;
    *)
        main "$1"
        ;;
esac
