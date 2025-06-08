#!/bin/bash

# Advanced E2E Test Scenarios
# This script contains more complex test scenarios

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"vertikal-e2e"}
TEST_NAMESPACE=${TEST_NAMESPACE:-"vertikal-test-advanced"}

check_cluster() {
    check_cluster_health "$CLUSTER_NAME"
    kubectl config use-context "kind-$CLUSTER_NAME"
}

create_test_namespace() {
    log "Creating test namespace: $TEST_NAMESPACE"
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

cleanup_test_namespace() {
    cleanup_namespace "$TEST_NAMESPACE"
}

# Test multiple VertikalApps in the same namespace
test_multiple_apps() {
    log "Testing multiple VertikalApps in the same namespace..."
    
    # Create first app
    local manifest1
    manifest1=$(create_vertikalapp_manifest "app1" "$TEST_NAMESPACE" "2" "nginx:latest" "80")
    apply_manifest "$manifest1"
    
    # Create second app
    local manifest2
    manifest2=$(create_vertikalapp_manifest "app2" "$TEST_NAMESPACE" "3" "httpd:latest" "80")
    apply_manifest "$manifest2"
    
    # Wait for both deployments
    wait_for_resource "deployment/app1" "available" "120s" "$TEST_NAMESPACE"
    wait_for_resource "deployment/app2" "available" "120s" "$TEST_NAMESPACE"
    
    # Verify both apps
    verify_resource_field "deployment" "app1" ".spec.replicas" "2" "$TEST_NAMESPACE"
    verify_resource_field "deployment" "app2" ".spec.replicas" "3" "$TEST_NAMESPACE"
    
    # Verify services
    kubectl get service app1 -n "$TEST_NAMESPACE"
    kubectl get service app2 -n "$TEST_NAMESPACE"
    
    log "Multiple apps test passed"
}

# Test rapid scaling operations
test_rapid_scaling() {
    log "Testing rapid scaling operations..."
    
    local app_name="rapid-scale-app"
    local manifest
    manifest=$(create_vertikalapp_manifest "$app_name" "$TEST_NAMESPACE" "1")
    apply_manifest "$manifest"
    
    wait_for_resource "deployment/$app_name" "available" "120s" "$TEST_NAMESPACE"
    
    # Rapid scale operations
    local scales=(5 2 8 1 10)
    for scale in "${scales[@]}"; do
        log "Scaling to $scale replicas..."
        manifest=$(create_vertikalapp_manifest "$app_name" "$TEST_NAMESPACE" "$scale")
        apply_manifest "$manifest"
        
        # Wait a bit for the scaling to be processed
        sleep 5
        
        # Verify the scale was applied
        verify_resource_field "deployment" "$app_name" ".spec.replicas" "$scale" "$TEST_NAMESPACE"
    done
    
    # Wait for final scaling to complete
    wait_for_resource "deployment/$app_name" "available" "180s" "$TEST_NAMESPACE"
    
    log "Rapid scaling test passed"
}

# Test different container images
test_different_images() {
    log "Testing different container images..."
    
    local images=("nginx:latest" "httpd:2.4" "busybox:latest")
    local app_counter=1
    
    for image in "${images[@]}"; do
        local app_name="image-test-$app_counter"
        log "Testing with image: $image"
        
        local manifest
        manifest=$(create_vertikalapp_manifest "$app_name" "$TEST_NAMESPACE" "1" "$image")
        apply_manifest "$manifest"
        
        wait_for_resource "deployment/$app_name" "available" "120s" "$TEST_NAMESPACE"
        
        # Verify the image is set correctly
        local actual_image
        actual_image=$(kubectl get deployment "$app_name" -n "$TEST_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
        if [[ "$actual_image" != "$image" ]]; then
            error "Expected image $image, got $actual_image"
        fi
        
        log "Image test passed for $image"
        ((app_counter++))
    done
    
    log "Different images test passed"
}

# Test update operations
test_update_operations() {
    log "Testing update operations..."
    
    local app_name="update-test-app"
    
    # Create initial app
    local manifest
    manifest=$(create_vertikalapp_manifest "$app_name" "$TEST_NAMESPACE" "2" "nginx:1.20")
    apply_manifest "$manifest"
    
    wait_for_resource "deployment/$app_name" "available" "120s" "$TEST_NAMESPACE"
    
    # Update image
    log "Updating image..."
    manifest=$(create_vertikalapp_manifest "$app_name" "$TEST_NAMESPACE" "2" "nginx:1.21")
    apply_manifest "$manifest"
    
    # Wait for rollout
    kubectl rollout status deployment/"$app_name" -n "$TEST_NAMESPACE" --timeout=180s
    
    # Verify image update
    local actual_image
    actual_image=$(kubectl get deployment "$app_name" -n "$TEST_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
    if [[ "$actual_image" != "nginx:1.21" ]]; then
        error "Expected image nginx:1.21, got $actual_image"
    fi
    
    # Update size
    log "Updating size..."
    manifest=$(create_vertikalapp_manifest "$app_name" "$TEST_NAMESPACE" "4" "nginx:1.21")
    apply_manifest "$manifest"
    
    wait_for_resource "deployment/$app_name" "available" "120s" "$TEST_NAMESPACE"
    verify_resource_field "deployment" "$app_name" ".spec.replicas" "4" "$TEST_NAMESPACE"
    
    log "Update operations test passed"
}

# Test error conditions and recovery
test_error_conditions() {
    log "Testing error conditions and recovery..."
    
    local app_name="error-test-app"
    
    # Test with invalid image
    log "Testing with invalid image..."
    local manifest
    manifest=$(create_vertikalapp_manifest "$app_name" "$TEST_NAMESPACE" "1" "invalid-image:nonexistent")
    apply_manifest "$manifest"
    
    # Wait a bit for the deployment to be created
    sleep 10
    
    # Check that deployment exists but pods may not be ready
    kubectl get deployment "$app_name" -n "$TEST_NAMESPACE"
    
    # Fix with valid image
    log "Fixing with valid image..."
    manifest=$(create_vertikalapp_manifest "$app_name" "$TEST_NAMESPACE" "1" "nginx:latest")
    apply_manifest "$manifest"
    
    wait_for_resource "deployment/$app_name" "available" "180s" "$TEST_NAMESPACE"
    
    log "Error conditions test passed"
}

# Test resource cleanup
test_resource_cleanup() {
    log "Testing resource cleanup..."
    
    local app_name="cleanup-test-app"
    
    # Create app
    local manifest
    manifest=$(create_vertikalapp_manifest "$app_name" "$TEST_NAMESPACE" "2")
    apply_manifest "$manifest"
    
    wait_for_resource "deployment/$app_name" "available" "120s" "$TEST_NAMESPACE"
    
    # Verify resources exist
    kubectl get deployment "$app_name" -n "$TEST_NAMESPACE"
    kubectl get service "$app_name" -n "$TEST_NAMESPACE"
    
    # Delete the VertikalApp
    delete_resource "vertikalapp" "$app_name" "$TEST_NAMESPACE"
    
    # Wait for resources to be cleaned up
    wait_for_deletion "deployment" "$app_name" "$TEST_NAMESPACE" 120
    wait_for_deletion "service" "$app_name" "$TEST_NAMESPACE" 120
    
    log "Resource cleanup test passed"
}

main() {
    local test_type="${1:-all}"
    
    log "Starting advanced e2e test: $test_type"
    print_environment
    
    check_cluster
    create_test_namespace
    
    # Run cleanup on exit
    trap cleanup_test_namespace EXIT
    
    case "$test_type" in
        "multiple")
            test_multiple_apps
            ;;
        "rapid-scaling")
            test_rapid_scaling
            ;;
        "images")
            test_different_images
            ;;
        "updates")
            test_update_operations
            ;;
        "errors")
            test_error_conditions
            ;;
        "cleanup")
            test_resource_cleanup
            ;;
        "all")
            test_multiple_apps
            test_rapid_scaling
            test_different_images
            test_update_operations
            test_error_conditions
            test_resource_cleanup
            ;;
        *)
            error "Unknown test type: $test_type. Available: multiple, rapid-scaling, images, updates, errors, cleanup, all"
            ;;
    esac
    
    log "Advanced e2e test '$test_type' completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [test-type]"
        echo ""
        echo "Advanced test types:"
        echo "  multiple       Test multiple VertikalApps in same namespace"
        echo "  rapid-scaling  Test rapid scaling operations"
        echo "  images         Test different container images"
        echo "  updates        Test update operations"
        echo "  errors         Test error conditions and recovery"
        echo "  cleanup        Test resource cleanup"
        echo "  all            Run all advanced tests"
        echo ""
        echo "Environment variables:"
        echo "  CLUSTER_NAME     Name of the kind cluster (default: vertikal-e2e)"
        echo "  TEST_NAMESPACE   Namespace for test resources (default: vertikal-test-advanced)"
        exit 0
        ;;
    "")
        main "all"
        ;;
    *)
        main "$1"
        ;;
esac
