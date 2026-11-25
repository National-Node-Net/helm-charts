# Python Vault initializer

This directory contains the Python port of the `cloud-secret` helper and the
Vault setup sidecar. `main.py` handles cloud-secret access, command dispatch, and Vault setup, while
`kubernetes.py` handles Kubernetes API access. It supports `aws`, `azure`, `gcp`, and `local` modes. Cloud
SDKs use their standard default credential chains, including workload identity.
Vault API operations use the HVAC Python client.

The image is built for both AMD64 and ARM64 from the project root:

```sh
docker buildx build --platform linux/amd64,linux/arm64 \
  -t <registry>/<repository>:<tag> --push \
  charts/federator-suite-vault-init
```

The default container command is `python /app/main.py`, which runs Vault setup. It reads the same
environment variables as the current setup script. It expects the existing
policy ConfigMap files at `/policys` and the Kubernetes service-account token
and CA certificate at their standard pod paths.

## Docker Compose debugger

The Compose stack runs a persistent Vault server, LocalStack Secrets Manager, and this image with
`debugpy`. The Python process waits for a debugger before executing:

```sh
cd charts/federator-suite-vault-init
docker compose -f docker-compose.debug.yml up --build
```

In VS Code, select **Attach to cloud-secret-py** from the Python debugger. Port `8200` exposes the
Vault UI/API and port `5678` is the debugger port. Vault data and LocalStack data are kept in named
volumes; remove them when you want a fresh initialization:

```sh
cd charts/federator-suite-vault-init
docker compose -f docker-compose.debug.yml down -v
```

The Compose profile disables Kubernetes-auth and Valkey setup because those require a Kubernetes
cluster and projected service-account files. The AWS Secrets Manager calls are redirected to
LocalStack through `AWS_ENDPOINT_URL`.

## Mocking Kubernetes auth

The Kubernetes-auth configuration is a Vault API call, not a call to the Kubernetes API. Unit tests
should therefore mock the Vault client and verify the call rather than requiring a Kubernetes cluster:

```python
from unittest.mock import Mock

vault = Mock()
vault.write(
    "auth/kubernetes/config",
    kubernetes_host="https://kubernetes.default.svc",
    kubernetes_ca_cert="ca-cert",
    disable_iss_validation=True,
)

vault.write.assert_called_once_with(
    "auth/kubernetes/config",
    kubernetes_host="https://kubernetes.default.svc",
    kubernetes_ca_cert="ca-cert",
    disable_iss_validation=True,
)
```

The Compose debugger uses the same principle. It provides a placeholder CA file and a local Vault
instance, but it does not pretend to be a Kubernetes cluster. Use unit-test mocks for Kubernetes
client behaviour; use Docker Compose when you need to debug the real Python process, Vault API,
LocalStack Secrets Manager, mounted files, environment variables, or debugger breakpoints.

To debug:

```sh
cd charts/federator-suite-vault-init
./scripts/reset-debug.sh
```

Grab the `/debug_files/.vscode/launch.json` profile and copy/update an existing launch.json

Then select **Attach to cloud-secret-py** in VS Code. The container waits on port `5678` before
running `main.py`, so attach first and then continue to the breakpoint. The reset script removes the
local Vault and LocalStack volumes, regenerates `debug_files`, and rebuilds the container.

