# Vault initialisation sidecar

This directory contains the Python application used by the `vault-setup`
container in the Vault StatefulSet. The application is packaged by the
`charts/federator-suite-vault-init/Dockerfile` and starts as:

```text
python /app/main.py
```

The container runs only on the ordinal-zero Vault pod. Other Vault pods log
that setup is being skipped and remain idle. After setup completes, the
ordinal-zero process also remains idle so that the sidecar is not restarted.

## Bootstrap flow

On the ordinal-zero pod, `main.py`:

1. waits for the Vault API;
2. initialises Vault, or recovers the root token from the configured secret
   backend;
3. unseals Vault using Shamir keys or waits for cloud auto-unseal;
4. joins the remaining Vault replicas to the Raft cluster;
5. enables the KV v2 mounts `secret/` and `node-net/`;
6. enables/configures Kubernetes auth and applies policy, role, and password
   rule files from `VAULT_CONFIGS_PATH`;
7. creates or preserves the Valkey and Sentinel credentials at
   `secret/apps/valkey`.

The bootstrap payload contains the Vault root token and recovery/unseal keys.
It is written to the configured secret backend on first initialisation and
read from there on subsequent runs. The Kubernetes `local` provider instead
stores the payload in a Kubernetes Secret and also writes the root token to
the certificate-manager token Secret.

## Configuration

In the Helm deployment, these variables are supplied by the
`vault-init-config` ConfigMap and the projected `vault-init-policys` volume:

| Variable | Purpose | Default |
| --- | --- | --- |
| `CLOUD_PROVIDER` | Secret backend: `aws`, `azure`, `gcp`, or `local` | `aws` |
| `SECRETS_MANAGER_SECRET_NAME` | Secret ID/name used for the bootstrap payload | required |
| `AWS_REGION` | AWS Secrets Manager region | `eu-west-2` |
| `AWS_ENDPOINT_URL` | Optional Secrets Manager endpoint, mainly for LocalStack/tests | unset |
| `AZURE_VAULT_NAME` | Azure Key Vault name | empty |
| `GCP_PROJECT` | Google Cloud project for Secret Manager | empty |
| `CERT_MANAGER_TOKEN_SECRET` | Kubernetes Secret name for the certificate-manager token in `local` mode | `certificate-manager-vault-token` |
| `NAMESPACE` | Kubernetes namespace used in `local` mode | `default` |
| `VAULT_ADDR` | Vault API address | `http://localhost:8200` |
| `VAULT_AUTO_UNSEAL` | Wait for cloud auto-unseal when `true`; submit stored Shamir keys when `false` | `true` |
| `VAULT_CONFIGS_PATH` | Directory containing `*-policy.hcl`, `*-role.json`, and `*-passwordrule.hcl` files | `secret/data` |
| `VAULT_KEY_SHARES` | Number of recovery/unseal key shares created during initialisation | `5` |
| `VAULT_KEY_THRESHOLD` | Threshold required for unseal/recovery | `3` |
| `VAULT_REPLICAS` | Number of Vault StatefulSet replicas | `1` |
| `LOG_LEVEL` | Python logging level | `INFO` |

Cloud SDKs use their normal default credential chains, including workload
identity. The `local` provider requires an in-cluster Kubernetes service
account, while the other providers require their corresponding cloud
credentials. Kubernetes auth setup also reads the service-account CA from
`/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`.

## Tests and image builds

Run the Python unit tests from the project directory:

```sh
cd charts/federator-suite-vault-init
./scripts/run-tests.sh
```

Use the Docker test stage when local Python dependencies are unavailable:

```sh
./scripts/run-tests.sh --docker
```

Build and push the runtime image to the configured ECR repository with the
provided script. It uses `linux/amd64,linux/arm64` by default and requires AWS
credentials, ECR access, and Docker Buildx:

```sh
./scripts/build-and-push-to-ecr.sh
```

Pass `--test` to build the test image, run the unit tests, and run the Trivy
scan. Override `PLATFORMS` or `TEST_PLATFORM` when needed.

## Docker Compose debugger

The Compose environment runs Vault, LocalStack Secrets Manager, and the
sidecar under `debugpy`. Generate its local Vault configuration, policy/role
files, CA certificate, and VS Code launch profile before the first start:

```sh
cd charts/federator-suite-vault-init
./scripts/generate-debug-files.sh
docker compose -f docker-compose.debug.yml up --build
```

The generator requires `openssl` and `yq`. The Python process waits for a
debugger on port `5678`; Vault is exposed on port `8200`, and LocalStack on
port `4566`. In VS Code, use the generated
`debug_files/.vscode/launch.json` profile named **Attach to cloud-secret-py**.

The Compose profile uses AWS mode with LocalStack, disables cloud auto-unseal,
and supplies a placeholder Kubernetes CA. It does not emulate a Kubernetes
API, so Kubernetes Secret access and real in-cluster authentication must be
tested with mocks or in a cluster.

To reset the named Vault and LocalStack volumes, regenerate all debug files,
and start a clean stack:

```sh
./scripts/reset-debug.sh
```

After the stack has initialised Vault, retrieve the bootstrap JSON from
LocalStack with:

```sh
./scripts/get-aws-vault-token.sh
```

The copied policy and role files are generated from
`charts/federator-suite/templates/vault/vault-init-policy.yaml`; regenerate
them after changing that Helm template.

## Kubernetes pod smoke test

To copy the current `main.py` into a running Vault setup container, compile it,
and check the startup phase log:

```sh
./scripts/test-in-k8spod.sh
```

Use `--run` to execute the copied script against the Vault service. The script
defaults to context `dev`, namespace `helm-federator-suite-bcc`, pod
`fs-bcc-vault-0`, and container `vault-setup`; override these with
`KUBE_CONTEXT`, `KUBE_NAMESPACE`, `KUBE_POD`, and `KUBE_CONTAINER`.

