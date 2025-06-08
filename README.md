# Vertikal - Kubernetes Controller

Vertikal is a Kubernetes controller that manages the deployment and lifecycle of applications in a Kubernetes cluster.

## Overview

Vertikal provides a custom resource definition (CRD) called `VertikalApp` that allows you to define your application deployment in a declarative way. The controller will create and manage the necessary Kubernetes resources (Deployments, Services, etc.) based on the `VertikalApp` specification.

## Features

- Declarative application deployment using custom resources
- Automatic creation and management of Kubernetes Deployments and Services
- Scaling of application replicas
- Status reporting of application health

## Getting Started

### Prerequisites

- Kubernetes cluster (v1.19+)
- kubectl (v1.19+)
- Go (v1.21+) for development
- Docker for building container images

### Installation

1. Clone the repository:

```bash
git clone https://github.com/naptime-dev/vertikal.git
cd vertikal
```

2. Install the CRDs:

```bash
make install
```

3. Deploy the controller:

```bash
make deploy
```

### Usage

1. Create a `VertikalApp` custom resource:

```yaml
apiVersion: vertikal.naptime.dev/v1alpha1
kind: VertikalApp
metadata:
  name: example-app
  namespace: default
spec:
  size: 2
  image: nginx:latest
  port: 80
```

2. Apply the custom resource:

```bash
kubectl apply -f config/samples/vertikal_v1alpha1_vertikalapp.yaml
```

3. Check the status of your application:

```bash
kubectl get vertikalapp example-app -n default
```

## Development

### Building the Controller

```bash
make build
```

### Running the Controller Locally

```bash
make run
```

### Running Tests

```bash
make test
```

### Building and Pushing the Docker Image

```bash
make docker-build docker-push IMG=<your-registry>/vertikal:tag
```

## Project Structure

- `api/` - API definitions (CRDs)
- `cmd/` - Main application entry points
- `pkg/` - Controller implementation
- `config/` - Kubernetes manifests
- `test/` - Test files

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.
