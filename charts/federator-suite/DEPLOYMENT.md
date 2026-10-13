# Deployment Guide

## End-to-end dev sequence

Use the README's [End-to-end dev sequence](README.md#end-to-end-dev-sequence) as the normal development workflow: prepare the target, validate, deploy, health-check, make a change, then upgrade and re-check.

Choose the target deliberately:

- **Local KIND** creates or reuses `federator-suite-kind-cluster` and is the default for safe chart development.
- **Cloud dev** uses the current `kubectl` context and an existing namespace. Confirm both before deploying.

## Local (KIND)

```bash
./scripts/check-prereqs.sh                # 1. Verify tools installed
make generate-certs ORG=bcc               # 2. Generate local mTLS certificates
make deploy-local ORG=bcc                 # 3. Deploy (creates cluster + installs chart)
make healthcheck ORG=bcc                  # 4. Verify pods, processes, logs
make port-forward-all                     # 5. Access UIs (JobRunr :8085, Kafka :8088, Valkey :5540, OPA :8181)
```

## Cloud (EKS / AKS / GKE)

```bash
make pre-deploy-check ENV=dev ORG=bcc     # 1. Validate config, cluster, secrets
make deploy ENV=dev ORG=bcc               # 2. Deploy (builds deps + installs chart)
make healthcheck ENV=dev ORG=bcc          # 3. Verify pods, processes, logs
make istio-status ENV=dev ORG=bcc         # 4. Verify Istio sidecars + resources
make port-forward-all ENV=dev ORG=bcc     # 5. Access UIs
```

## Iterative Updates

```bash
make upgrade ENV=dev ORG=bcc              # Fast upgrade (skips pre-checks)
make healthcheck ENV=dev ORG=bcc          # Verify
```

## Teardown

```bash
make stop-port-forwards                   # Stop port forwards
make uninstall ENV=dev ORG=bcc            # Uninstall release + delete PVCs
make destroy-cluster                      # Delete KIND cluster (local only)
```

`make uninstall` deletes release PVCs. Use it only when removing the associated data is intentional.
