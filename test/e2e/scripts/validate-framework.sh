#!/bin/bash

# E2E Test Framework Validation
# This script validates that the e2e framework is properly set up

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

validate_scripts() {
    log "Validating e2e scripts..."
    
    local scripts=(
        "setup-cluster.sh"
        "teardown-cluster.sh"
        "run-test.sh"
        "run-advanced-tests.sh"
        "run-suite.sh"
        "utils.sh"
    )
    
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ ! -f "$script_path" ]]; then
            error "Script not found: $script_path"
        fi
        
        if [[ ! -x "$script_path" ]]; then
            error "Script not executable: $script_path"
        fi
        
        # Basic syntax check
        if ! bash -n "$script_path"; then
            error "Syntax error in script: $script_path"
        fi
        
        info "✓ $script"
    done
    
    log "All scripts validated successfully"
}

validate_dependencies() {
    log "Validating dependencies..."
    
    local required_commands=(
        "kind"
        "kubectl" 
        "docker"
        "make"
        "go"
    )
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            info "✓ $cmd"
        else
            warn "✗ $cmd (not found)"
        fi
    done
    
    # Check Docker status
    if docker info &> /dev/null; then
        info "✓ Docker (running)"
    else
        warn "✗ Docker (not running)"
    fi
    
    log "Dependency check completed"
}

validate_makefile_targets() {
    log "Validating Makefile targets..."
    
    local targets=(
        "e2e-setup"
        "e2e-teardown"
        "e2e-test-basic"
        "e2e-test-scaling"
        "e2e-test-deletion"
        "e2e-test-go"
        "e2e-test-advanced"
        "e2e-suite"
        "e2e-help"
    )
    
    # Go to project root
    cd "$SCRIPT_DIR/../../.."
    
    for target in "${targets[@]}"; do
        if make -n "$target" &> /dev/null; then
            info "✓ make $target"
        else
            warn "✗ make $target (not found)"
        fi
    done
    
    log "Makefile targets validated"
}

validate_github_actions() {
    log "Validating GitHub Actions..."
    
    local workflow_file="$SCRIPT_DIR/../../../.github/workflows/e2e-test.yaml"
    
    if [[ -f "$workflow_file" ]]; then
        info "✓ GitHub Actions workflow exists"
        
        # Basic YAML syntax check
        if command -v yamllint &> /dev/null; then
            if yamllint "$workflow_file" &> /dev/null; then
                info "✓ Workflow YAML syntax"
            else
                warn "✗ Workflow YAML syntax issues"
            fi
        else
            info "? Workflow YAML syntax (yamllint not available)"
        fi
    else
        warn "✗ GitHub Actions workflow not found"
    fi
    
    log "GitHub Actions validation completed"
}

validate_project_structure() {
    log "Validating project structure..."
    
    # Go to project root
    cd "$SCRIPT_DIR/../../.."
    
    local required_files=(
        "Makefile"
        "go.mod"
        "config/crd/bases/vertikal.werner.io_vertikalapps.yaml"
        "cmd/manager/main.go"
        "pkg/controller/vertikalapp/vertikalapp_controller.go"
        "test/e2e/kind-config.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            info "✓ $file"
        else
            warn "✗ $file (not found)"
        fi
    done
    
    log "Project structure validation completed"
}

run_help_tests() {
    log "Testing help commands..."
    
    local help_commands=(
        "$SCRIPT_DIR/setup-cluster.sh --help"
        "$SCRIPT_DIR/teardown-cluster.sh --help" 
        "$SCRIPT_DIR/run-test.sh --help"
        "$SCRIPT_DIR/run-advanced-tests.sh --help"
        "$SCRIPT_DIR/run-suite.sh --help"
    )
    
    for cmd in "${help_commands[@]}"; do
        if $cmd &> /dev/null; then
            info "✓ $cmd"
        else
            warn "✗ $cmd (failed)"
        fi
    done
    
    # Test make help
    cd "$SCRIPT_DIR/../../.."
    if make e2e-help &> /dev/null; then
        info "✓ make e2e-help"
    else
        warn "✗ make e2e-help (failed)"
    fi
    
    log "Help commands validated"
}

print_summary() {
    log "E2E Framework Validation Summary"
    echo "================================"
    echo "The e2e testing framework has been set up with:"
    echo ""
    echo "📁 Directory Structure:"
    echo "   test/e2e/scripts/         - Modular shell scripts"
    echo "   test/e2e/README.md        - Comprehensive documentation"
    echo ""
    echo "🚀 Quick Start:"
    echo "   make e2e-suite            - Run complete test suite"
    echo "   make e2e-help             - Show all available commands"
    echo ""
    echo "🛠️ Individual Components:"
    echo "   make e2e-setup            - Setup kind cluster"
    echo "   make e2e-test-basic       - Run basic tests"
    echo "   make e2e-test-advanced    - Run advanced tests"
    echo "   make e2e-teardown         - Cleanup cluster"
    echo ""
    echo "🔧 Advanced Usage:"
    echo "   SKIP_TEARDOWN=true make e2e-suite     - Keep cluster for debugging"
    echo "   TEST_TYPES=basic,scaling make e2e-suite - Run specific tests"
    echo ""
    echo "📋 Features:"
    echo "   ✓ Kind cluster auto-detection (Docker/Podman)"
    echo "   ✓ Modular test scripts with individual execution"
    echo "   ✓ Comprehensive Makefile targets"
    echo "   ✓ GitHub Actions CI integration"
    echo "   ✓ Advanced test scenarios"
    echo "   ✓ Proper cleanup and error handling"
    echo ""
    echo "📖 For detailed information, see:"
    echo "   test/e2e/README.md"
    echo "================================"
}

main() {
    log "Starting e2e framework validation..."
    print_environment
    
    validate_scripts
    validate_dependencies
    validate_makefile_targets
    validate_github_actions
    validate_project_structure
    run_help_tests
    
    print_summary
    
    log "E2E framework validation completed!"
}

case "${1:-}" in
    --help|-h)
        echo "Usage: $0"
        echo ""
        echo "This script validates the e2e testing framework setup."
        echo "It checks scripts, dependencies, Makefile targets, and project structure."
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown argument: $1. Use --help for usage information."
        ;;
esac
