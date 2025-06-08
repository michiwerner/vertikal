# E2E Testing Guide

This directory contains a comprehensive end-to-end (e2e) testing framework for the Vertikal operator. The tests are modularized into shell scripts that can be run individually or as part of a complete test suite.

## Overview

The e2e testing framework consists of:

- **Cluster Management**: Automated setup and teardown of kind clusters
- **Modular Tests**: Individual test scenarios that can be run separately
- **Advanced Scenarios**: Complex test cases for comprehensive validation
- **CI Integration**: GitHub Actions workflows for automated testing
- **Make Targets**: Convenient Makefile targets for all operations

## Directory Structure

```
test/e2e/
├── scripts/
│   ├── setup-cluster.sh         # Kind cluster setup with auto-detection
│   ├── teardown-cluster.sh      # Cluster cleanup
│   ├── run-test.sh             # Individual test runner
│   ├── run-advanced-tests.sh   # Advanced test scenarios
│   ├── run-suite.sh            # Complete test suite runner
│   └── utils.sh                # Common utilities and functions
├── vertikalapp_test.go         # Original Go e2e tests
└── README.md                   # This file
```

## Quick Start

### 1. Setup and Run Basic Tests

```bash
# Setup cluster, run basic tests, cleanup
make e2e-suite

# Or step by step:
make e2e-setup          # Setup cluster
make e2e-test-basic     # Run basic tests
make e2e-teardown       # Cleanup
```

### 2. Run Individual Tests

```bash
make e2e-test-basic     # Basic VertikalApp creation
make e2e-test-scaling   # Scaling operations
make e2e-test-deletion  # Resource deletion
make e2e-test-go        # Original Go tests
```

### 3. Run Advanced Tests

```bash
make e2e-test-advanced           # All advanced tests
make e2e-test-advanced-multiple  # Multiple apps test
make e2e-test-advanced-scaling   # Rapid scaling test
make e2e-test-advanced-images    # Different images test
```

## Test Categories

### Basic Tests (`run-test.sh`)

| Test Type | Description |
|-----------|-------------|
| `basic` | Creates a VertikalApp and verifies deployment and service creation |
| `scaling` | Tests scaling operations from 1→3 replicas |
| `deletion` | Tests VertikalApp deletion and resource cleanup |
| `go` | Runs the original Go-based e2e tests |
| `all` | Runs all basic test types |

### Advanced Tests (`run-advanced-tests.sh`)

| Test Type | Description |
|-----------|-------------|
| `multiple` | Multiple VertikalApps in the same namespace |
| `rapid-scaling` | Rapid consecutive scaling operations |
| `images` | Different container images (nginx, httpd, busybox) |
| `updates` | Update operations (image and size changes) |
| `errors` | Error conditions and recovery scenarios |
| `cleanup` | Resource cleanup verification |
| `all` | Runs all advanced test types |

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `vertikal-e2e` | Name of the kind cluster |
| `KIND_CONFIG` | `test/e2e/kind-config.yaml` | Kind cluster configuration |
| `CONTROLLER_IMAGE` | `controller:latest` | Controller Docker image |
| `KUBERNETES_VERSION` | (auto) | Kubernetes version for kind cluster |
| `TEST_NAMESPACE` | `vertikal-test` | Namespace for test resources |
| `SKIP_SETUP` | `false` | Skip cluster setup |
| `SKIP_TEARDOWN` | `false` | Skip cluster teardown |
| `TEST_TYPES` | `all` | Comma-separated test types to run |

### Examples

```bash
# Use custom cluster name
CLUSTER_NAME=my-test-cluster make e2e-suite

# Run specific tests only
TEST_TYPES=basic,scaling make e2e-suite

# Keep cluster for debugging
SKIP_TEARDOWN=true make e2e-suite

# Run on existing cluster
SKIP_SETUP=true SKIP_TEARDOWN=true make e2e-suite

# Use specific Kubernetes version
KUBERNETES_VERSION=v1.28.0 make e2e-setup
```

## Kind Cluster Features

### Auto-Detection

The setup script automatically detects and uses the available container runtime:
- **Docker**: Preferred when available and running
- **Podman**: Used when Docker is not available
- **Error**: If neither is available

### Cluster Configuration

The kind cluster is configured with:
- Control plane node with ingress-ready label
- Port forwarding for HTTP (80) and HTTPS (443)
- Configurable Kubernetes version
- Automatic image loading for the controller

## CI Integration

### GitHub Actions

The `.github/workflows/e2e-test.yaml` workflow:
- **Matrix Strategy**: Runs different test types in parallel
- **Full Suite**: Runs complete test suite
- **Automatic Cleanup**: Always tears down cluster
- **Multi-OS Support**: Can be extended for different operating systems

### Workflow Structure

```yaml
jobs:
  e2e-test:
    strategy:
      matrix:
        test-type: [basic, scaling, deletion, go]
    # Runs each test type in parallel

  e2e-full-suite:
    # Runs complete test suite including advanced tests
```

## Development Workflow

### Adding New Tests

1. **Basic Tests**: Add test functions to `run-test.sh`
2. **Advanced Tests**: Add test functions to `run-advanced-tests.sh`
3. **Makefile**: Add new targets in the E2E Testing section
4. **CI**: Update GitHub Actions workflow if needed

### Test Development Guidelines

1. Use the utility functions from `utils.sh`
2. Always include proper cleanup in tests
3. Use meaningful test names and descriptions
4. Verify both positive and negative scenarios
5. Include proper timeout handling

### Example Test Function

```bash
test_my_feature() {
    log "Running my feature test..."
    
    # Create test resources
    local manifest
    manifest=$(create_vertikalapp_manifest "my-app" "$TEST_NAMESPACE" "2")
    apply_manifest "$manifest"
    
    # Wait for resources
    wait_for_resource "deployment/my-app" "available" "120s" "$TEST_NAMESPACE"
    
    # Verify expectations
    verify_resource_field "deployment" "my-app" ".spec.replicas" "2" "$TEST_NAMESPACE"
    
    log "My feature test passed"
}
```

## Troubleshooting

### Common Issues

1. **Cluster Creation Fails**
   ```bash
   # Check Docker/Podman status
   docker info
   # or
   podman info
   
   # Check kind version
   kind version
   ```

2. **Controller Not Ready**
   ```bash
   # Check controller logs
   kubectl logs -n vertikal-system deployment/vertikal-controller-manager
   
   # Check controller status
   kubectl get deployment -n vertikal-system
   ```

3. **Tests Timeout**
   ```bash
   # Check cluster health
   kubectl get nodes
   kubectl get pods --all-namespaces
   
   # Increase timeout in test scripts
   TIMEOUT=300s make e2e-test-basic
   ```

### Debug Mode

To keep the cluster for investigation:

```bash
# Run tests but keep cluster
SKIP_TEARDOWN=true make e2e-suite

# Inspect cluster
kubectl get all --all-namespaces
kubectl describe vertikalapp -A

# Cleanup when done
make e2e-teardown
```

### Logs and Diagnostics

```bash
# Controller logs
kubectl logs -n vertikal-system deployment/vertikal-controller-manager -f

# Test namespace resources
kubectl get all -n vertikal-test

# Kind cluster info
kind get clusters
kubectl cluster-info --context kind-vertikal-e2e
```

## Best Practices

1. **Isolation**: Each test should be independent and clean up after itself
2. **Timeouts**: Always use reasonable timeouts for resource operations
3. **Verification**: Verify both the desired state and cleanup
4. **Logging**: Use proper logging levels (log, info, warn, error)
5. **Modularity**: Keep tests focused on specific functionality
6. **Documentation**: Document test purpose and expected behavior

## Contributing

When adding new tests:

1. Follow the existing naming conventions
2. Add appropriate Makefile targets
3. Update this README if adding new categories
4. Test locally before submitting PR
5. Consider CI impact (parallel execution, timeouts)

## Help

For detailed help on available commands:

```bash
make e2e-help
```

For script-specific help:

```bash
./test/e2e/scripts/setup-cluster.sh --help
./test/e2e/scripts/run-test.sh --help
./test/e2e/scripts/run-suite.sh --help
```
