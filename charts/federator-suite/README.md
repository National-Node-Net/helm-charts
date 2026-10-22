# Federator Suite Helm Chart

Helm chart for deploying Federator Suite to local KIND and cloud Kubernetes (EKS, AKS, GKE).

## Index

- [Quick Start](#quick-start)
- [End-to-end dev sequence](#end-to-end-dev-sequence)
- [TODOs for handover](#todos-for-handover)
- [Directory Structure](#directory-structure)
- [Configuration Switches](#configuration-switches)
- [Values Precedence](#values-precedence)
- [Make Commands](#make-commands)
- [Prerequisites](#prerequisites)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Local (KIND)

```bash
make deploy-local ORG=bcc
```

### Dev (EKS / AKS / GKE)

```bash
make deploy ENV=dev ORG=bcc
```

### Iterative Update

```bash
make upgrade ENV=dev ORG=bcc
```

## End-to-end dev sequence

Use this sequence when developing or testing the chart. Choose **one** target:

- **Local KIND**: safe for chart and integration work on your machine. It creates or reuses the `federator-suite-kind-cluster` cluster.
- **Cloud dev**: deploys to the Kubernetes context currently selected in `kubectl`. It does not create a cluster or namespace, so confirm the context before continuing.

Replace `bcc` only when you are intentionally working on another organisation overlay.

### 1. Prepare the target

For local development, check the required tools and generate local mTLS material once (or again when the local certificate inputs change):

```bash
./scripts/check-prereqs.sh
make generate-certs ORG=bcc
```

For cloud development, first confirm you are connected to the intended cluster and namespace:

```bash
kubectl config current-context
make pre-deploy-check ENV=dev ORG=bcc
```

### 2. Validate before deploying

Render and lint the chart using the same values that will be deployed:

```bash
make validate ENV=local ORG=bcc  # local KIND
make validate ENV=dev ORG=bcc    # cloud dev
```

### 3. Deploy

Use the full deploy command for a first install or after changing prerequisites. It builds chart dependencies, installs or upgrades the release, and waits for Kubernetes resources:

```bash
make deploy-local ORG=bcc        # local KIND
make deploy ENV=dev ORG=bcc      # cloud dev
```

### 4. Check that it is healthy

Run the health check, then inspect logs if it reports a problem:

```bash
make healthcheck ENV=local ORG=bcc  # local KIND
make healthcheck ENV=dev ORG=bcc    # cloud dev
make logs ENV=dev ORG=bcc            # recent logs from all components
```

For a local deployment, `make port-forward-all` exposes the JobRunr, Kafka, Valkey, Vault, and OPA interfaces on localhost. Stop them later with `make stop-port-forwards`.

### 5. Make and test a change

After changing templates or values, validate first, then use the faster upgrade command:

```bash
make validate ENV=dev ORG=bcc
make upgrade ENV=dev ORG=bcc
make healthcheck ENV=dev ORG=bcc
```

Use `ENV=local` in these commands when working in KIND. Use `make deploy` instead of `make upgrade` when you need its pre-deploy checks or dependency build.

### 6. Clean up deliberately

```bash
make stop-port-forwards
make uninstall ENV=local ORG=bcc  # removes the release and its PVCs
make destroy-cluster              # local KIND only
```

`make uninstall` deletes the release **and its PVCs**. Do not run it against a cloud namespace unless deleting the deployed data is intentional.

## TODOs for handover

- [ ] Confirm the approved BCC certificate identity and certificate blobs in `values/overrides/dev/secrets/bcc-secrets.yaml`; keep the certificate-manager subject/SAN values in `values/overrides/dev/bcc.yaml` aligned with that identity before enabling issuance.
- [ ] Complete the Management Node certificate-automation setup for BCC: enable organisation automation, seed the bootstrap certificate into the Federator Suite Vault, and confirm the renewal flow end to end.
- [ ] Restrict the Keycloak `FEDERATOR_BCC` client certificate DN matcher and verify that its certificate-automation roles include `create_keys`, `sign_certificate`, and `access_public_certificates`.
- [ ] Decide how certificate-manager output is delivered to federator-server/client; the applications load certificates at startup and require a rolling restart after rotation.
- [ ] Provision HEG Azure infrastructure values with Terraform: tenant ID, Key Vault name, unseal key name, Workload Identity client ID, and the Vault credential secret name; replace all `PLACEHOLDER_HEG_*` values before deploying HEG.
- [ ] Validate the HEG Azure setup sidecar image and permissions end to end, including Azure Key Vault access, Vault auto-unseal, Raft membership, Kubernetes auth, and certificate-manager access.
- [ ] Deploy HMRC to the GKE context `dev-ndtp-gke` with `ENV=dev ORG=hmrc` and record the result in the deployment handover.
- [ ] Validate HMRC GCP Vault auto-unseal using Cloud KMS (`development-486319`, `dev-fed-vault-keyring`, `dev-fed-vault-unseal-key`) and confirm all Vault replicas join one Raft cluster.
- [ ] Validate the HMRC GCP Secret Manager path `projects/598715601744/secrets/dev-fed-vault-secrets`, including persistence and recovery of Vault credentials after a Vault pod restart.
- [ ] Validate the GKE Kubernetes auth binding from the HMRC certificate-manager ServiceAccount to the Vault `certificate-manager` role, then confirm certificate-manager can read and write the `node-net` KV mount.

## Directory Structure

```text
federator-suite/
├── Chart.yaml                  # Chart metadata and dependencies
├── Makefile                    # Deploy / test / cleanup commands
├── kind-config.yaml            # KIND cluster config
├── scripts/
│   ├── check-prereqs.sh        # Checks required tools
│   ├── generate-certs.sh       # Generates local certs, updates secrets values
│   ├── test-render.sh          # Renders chart across scenarios
│   └── validate-values.sh     # Aligns enabled/external flags
├── templates/
│   ├── _helpers.tpl            # Shared helper functions
│   ├── NOTES.txt               # Post-install summary (shown by Helm)
│   ├── VALIDATION.yaml         # Pre-install/pre-upgrade validation hook
│   ├── server/                 # Federator server resources
│   ├── client/                 # Federator client resources
│   ├── configmaps/             # Application config
│   ├── secrets/                # Kubernetes Secret templates
│   ├── vault/                  # Vault sidecar setup ConfigMap + supporting RBAC/SA
│   ├── certificate-manager/    # Certificate manager deployment, PVC, secrets
│   ├── opa/                    # OPA (Open Policy Agent) PDP — Deployment, Service, ConfigMap, SA
│   ├── istio/                  # Optional Istio resources
│   ├── kafka-ui/               # Kafka UI resources
│   └── valkey-ui/              # Valkey UI resources
├── files/
│   └── opa-policies/            # Rego policy files loaded verbatim into the OPA ConfigMap
├── values/
│   ├── common-values.yaml      # Global defaults
│   ├── kafka.yaml               # Kafka defaults + external toggle
│   ├── valkey.yaml               # Valkey defaults + external toggle
│   ├── vault.yaml                # Vault defaults (HA Raft, auto-unseal, dev mode)
│   ├── certificate-manager.yaml  # Certificate manager defaults
│   ├── opa.yaml                  # OPA PDP defaults (standalone Deployment, not a sidecar)
│   ├── federator.yaml          # Server/client defaults
│   ├── kafka-ui.yaml           # Kafka UI defaults
│   ├── valkey-ui.yaml          # Valkey UI defaults
│   ├── istio.yaml              # Istio defaults
│   └── overrides/
│       ├── local/              # KIND overlays (local.yaml, bcc.yaml, secrets.yaml, …)
│       ├── dev/                # Dev overlays  (bcc.yaml, env.yaml, secrets/…)
│       └── prod/               # Prod overlays (secrets/…)
└── charts/                     # Vendored dependency charts (valkey, vault)
```

## Configuration Switches

| Switch | Default | Effect |
|--------|---------|--------|
| `kafka.external` | `false` | `false` = Bitnami Kafka in-cluster · `true` = External (MSK, Event Hubs, Managed Kafka) |
| `kafka.enabled` | `false` | Controls Kafka subchart. `true` when in-cluster, `false` when external |
| `valkey.external` | `false` | `false` = Valkey in-cluster · `true` = External Redis/Memorystore |
| `valkey.enabled` | `true` | Controls Valkey subchart. Set `false` when external |
| `vault.cloudProvider` | (auto) | Cloud provider for auto-unseal. Auto-derived from `global.clusterType` (`eks`→`aws`, `aks`→`azure`, `gke`→`gcp`). Set explicitly to override. |
| `vault.devMode` | `false` | Use in-memory Vault without KMS auto-unseal (for KIND/local development) |
| `opa.enabled` | `true` | Deploys the OPA (Open Policy Agent) PDP as its own Deployment + ClusterIP Service (not a sidecar). No PEP wired up to it yet — infra ready for future policy integration. |
| `serviceMesh.istio.enabled` | `false` | Deploys Istio resources (Gateway, VirtualService, DestinationRule, PeerAuthentication, AuthorizationPolicy). OPA always opts out of sidecar injection regardless of this switch. |
| `kafkaUi.enabled` | `false` | Deploy Kafka UI |
| `valkeyUi.enabled` | `false` | Deploy Valkey UI |

Each org override file (e.g. `dev/bcc.yaml`) is self-contained — cloud config, org settings, annotations, storage, and connection details in one file.

## Values Precedence

Helm applies files left to right; last file wins. Order used by the Makefile:

1. `values/common-values.yaml` → `kafka.yaml` → `valkey.yaml` → `vault.yaml` → `certificate-manager.yaml` → `opa.yaml` → `federator.yaml` → `kafka-ui.yaml` → `valkey-ui.yaml` → `istio.yaml`
2. Environment override (`values/overrides/{env}/{org}.yaml`)
3. Secrets file (`values/overrides/{env}/secrets/{org}-secrets.yaml`)
4. CLI `--set` flags (highest priority)

Dependencies (Bitnami Kafka repo + local Valkey subchart) are built automatically by `make deploy*`.

## Make Commands

| Command | Purpose |
|---|---|
| **Deploy** | |
| `make deploy ENV=dev ORG=bcc` | Full deploy with pre-checks |
| `make deploy-local ORG=bcc` | Deploy to local KIND cluster |
| `make upgrade ENV=dev ORG=bcc` | Fast Helm upgrade (no pre-checks) |
| **Validation** | |
| `make pre-deploy-check ENV=dev ORG=bcc` | Run all pre-deploy checks |
| `make validate ENV=dev ORG=bcc` | Validate config files + lint |
| `make check-cluster ENV=dev ORG=bcc` | Check cluster connectivity |
| `make check-secrets ENV=dev ORG=bcc` | Verify secrets file exists |
| **Testing** | |
| `make test ENV=dev ORG=bcc` | Run test-render + lint |
| `make test-render ENV=dev ORG=bcc` | Render templates, catch issues early |
| `make lint ENV=dev ORG=bcc` | Helm lint |
| `make template ENV=dev ORG=bcc` | Render full manifests to stdout |
| `make debug ENV=dev ORG=bcc` | Show resolved values + rendered templates |
| **Status & Health** | |
| `make status ENV=dev ORG=bcc` | Show all pods, services, PVCs, jobs |
| `make healthcheck ENV=dev ORG=bcc` | Pod readiness + process checks + error scan |
| **Logs** | |
| `make logs-server` | Tail federator-server logs |
| `make logs-client` | Tail federator-client logs |
| `make logs-opa` | Tail OPA logs |
| `make logs` | Last 50 lines from all pods |
| **Port Forwarding** | |
| `make port-forward-all` | Forward Kafka UI (8088), Valkey UI (5540), JobRunr (8085), Vault UI (8200), OPA (8181) |
| `make stop-port-forwards` | Kill all port forwards |
| `make port-forward-status` | Show active port forwards |
| **Istio** | |
| `make istio-enable ENV=dev ORG=bcc` | Enable Istio injection on namespace |
| `make istio-disable ENV=dev ORG=bcc` | Disable Istio injection on namespace |
| `make istio-status ENV=dev ORG=bcc` | Check Istio injection, sidecars, resources |
| **Certificates** | |
| `make generate-certs ORG=org1` | Generate local mTLS certificates |
| **Cleanup** | |
| `make uninstall ENV=dev ORG=bcc` | Uninstall release + delete PVCs |
| `make uninstall-keep-data ENV=dev ORG=bcc` | Uninstall release, keep PVCs |
| `make destroy-cluster` | Delete KIND cluster (local only) |
| `make clean` | Clean generated files (Chart.lock, certs) |
| `make clean-all ENV=local` | Uninstall + destroy cluster + clean |

## Prerequisites

- [Kubectl](https://kubernetes.io/docs/tasks/tools/) (v1.28+), [Helm](https://helm.sh/) (v3.12+), [Make](https://www.gnu.org/software/make/)

Additional for local KIND:

- [Docker](https://www.docker.com/) (v20+), [Kind](https://kind.sigs.k8s.io/) (v0.20+)
- [OpenSSL](https://www.openssl.org/), Java `keytool`, [yq](https://mikefarah.gitbook.io/yq/)

### Local KIND Flow

```bash
./scripts/check-prereqs.sh        # 1. Verify tools
make generate-certs ORG=org1      # 2. Generate certs (if needed)
make deploy-local ORG=bcc         # 3. Deploy
make healthcheck ORG=bcc          # 4. Verify
```

### Secrets

Secret files are git-ignored. For dev/prod, prefer cloud secret managers synced via CSI driver over Helm-managed secrets.

## Troubleshooting

```bash
make healthcheck ENV=dev ORG=bcc                                        # Pod/service/process/log check
kubectl logs -l app=federator-server -n helm-ia-federation --tail=100   # Server logs
kubectl logs -l app=federator-client -n helm-ia-federation --tail=100   # Client logs
kubectl get pods -n helm-ia-federation                                  # Pod status
```

### Certificate Issues

```bash
base64 -w 0 client.p12                                          # Encode P12
kubectl get secret federation-client-p12 -n ia-federation -o yaml  # Verify secret
```
