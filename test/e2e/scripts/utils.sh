#!/bin/bash

# E2E Test Utilities
# Common functions used across e2e test scripts

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Logging functions
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

# Check if a command exists
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        error "$cmd is not installed. Please install $cmd first."
    fi
}

# Wait for a resource to be ready
wait_for_resource() {
    local resource="$1"
    local condition="$2"
    local timeout="${3:-120s}"
    local namespace="${4:-default}"
    
    log "Waiting for $resource to be $condition (timeout: $timeout)..."
    
    if [[ "$namespace" != "default" ]]; then
        kubectl wait --for=condition="$condition" --timeout="$timeout" "$resource" -n "$namespace"
    else
        kubectl wait --for=condition="$condition" --timeout="$timeout" "$resource"
    fi
}

# Wait for a resource to be deleted
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-default}"
    local timeout="${4:-120}"
    
    log "Waiting for $resource_type/$resource_name to be deleted..."
    
    local count=0
    while kubectl get "$resource_type" "$resource_name" -n "$namespace" &> /dev/null; do
        if [[ $count -ge $timeout ]]; then
            error "Timeout waiting for $resource_type/$resource_name to be deleted"
        fi
        info "Waiting for $resource_type/$resource_name to be deleted... ($count/$timeout)"
        sleep 1
        ((count++))
    done
    
    log "$resource_type/$resource_name deleted successfully"
}

# Apply a YAML manifest
apply_manifest() {
    local manifest="$1"
    
    log "Applying manifest..."
    echo "$manifest" | kubectl apply -f -
}

# Delete a resource by name and type
delete_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-default}"
    
    log "Deleting $resource_type/$resource_name in namespace $namespace..."
    kubectl delete "$resource_type" "$resource_name" -n "$namespace" --ignore-not-found=true
}

# Get resource field value
get_resource_field() {
    local resource_type="$1"
    local resource_name="$2"
    local field_path="$3"
    local namespace="${4:-default}"
    
    kubectl get "$resource_type" "$resource_name" -n "$namespace" -o jsonpath="{$field_path}"
}

# Verify resource field value
verify_resource_field() {
    local resource_type="$1"
    local resource_name="$2"
    local field_path="$3"
    local expected_value="$4"
    local namespace="${5:-default}"
    
    local actual_value
    actual_value=$(get_resource_field "$resource_type" "$resource_name" "$field_path" "$namespace")
    
    if [[ "$actual_value" != "$expected_value" ]]; then
        error "Expected $field_path to be '$expected_value', but got '$actual_value'"
    fi
    
    log "Verified $resource_type/$resource_name $field_path = $expected_value"
}

# Create a test VertikalApp manifest
create_vertikalapp_manifest() {
    local name="$1"
    local namespace="$2"
    local size="$3"
    local image="${4:-nginx:latest}"
    local port="${5:-80}"
    
    cat <<EOF
apiVersion: vertikal.naptime.dev/v1alpha1
kind: VertikalApp
metadata:
  name: $name
  namespace: $namespace
spec:
  size: $size
  image: $image
  port: $port
EOF
}

# Check cluster health
check_cluster_health() {
    local cluster_name="$1"
    
    log "Checking cluster health for $cluster_name..."
    
    # Check if cluster exists
    if ! kind get clusters | grep -q "^$cluster_name$"; then
        error "Cluster $cluster_name does not exist"
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info --context "kind-$cluster_name" &> /dev/null; then
        error "Cannot connect to cluster $cluster_name"
    fi
    
    # Check nodes are ready
    kubectl get nodes --context "kind-$cluster_name" -o wide
    
    # Check system pods
    kubectl get pods -n kube-system --context "kind-$cluster_name"
    
    # Check controller
    if kubectl get deployment vertikal-controller-manager -n vertikal-system --context "kind-$cluster_name" &> /dev/null; then
        kubectl get deployment vertikal-controller-manager -n vertikal-system --context "kind-$cluster_name"
        kubectl get pods -n vertikal-system --context "kind-$cluster_name"
    else
        warn "Controller not deployed yet"
    fi
    
    log "Cluster health check completed"
}

# Generate a unique test name
generate_test_name() {
    local prefix="${1:-test}"
    local timestamp=$(date +%s)
    echo "${prefix}-${timestamp}"
}

# Cleanup function that can be used in traps
cleanup_namespace() {
    local namespace="$1"
    
    if [[ -n "$namespace" ]] && kubectl get namespace "$namespace" &> /dev/null; then
        warn "Cleaning up namespace: $namespace"
        kubectl delete namespace "$namespace" --ignore-not-found=true
        
        # Wait for namespace to be fully deleted
        local count=0
        while kubectl get namespace "$namespace" &> /dev/null && [[ $count -lt 60 ]]; do
            sleep 1
            ((count++))
        done
    fi
}

# Print environment information
print_environment() {
    log "Environment Information:"
    echo "========================"
    echo "Date: $(date)"
    echo "Kubernetes Client Version: $(kubectl version --client --short 2>/dev/null || echo "Unknown")"
    echo "Kind Version: $(kind version 2>/dev/null || echo "Unknown")"
    echo "Docker Version: $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo "Unknown")"
    echo "Go Version: $(go version 2>/dev/null || echo "Unknown")"
    echo "Operating System: $(uname -s)"
    echo "Architecture: $(uname -m)"
    echo "========================"
}
