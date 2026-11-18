Run from the repository root on Linux with Python 3, Helm, jq, Mike Farah yq, and Vault installed:

```sh
python3 charts/federator-suite-vault-init/tests/audit.py
```

From the Vault-init project directory, use the test runner for the unit tests:

```sh
cd charts/federator-suite-vault-init
./scripts/run-tests.sh
```

This audit is separate from the vault-init Python tests and is not part of the vault-init CI job.

The audit creates a fresh temporary evidence directory and prints its path. It renders the current chart, runs provider/failure branch checks with mocked cloud CLIs and Kubernetes calls, and starts a local in-memory Vault server for initialization and restart tests. It does not access a real cloud backend or Kubernetes cluster. The tests use no real credentials.

A nonzero exit means one or more checks failed. The recorded initial run had 73/78 passing checks; see REPORT.md and recorded-results.json. This is a diagnostic suite with known failures, not a claim that the current chart is ready to deploy. It also requires the two setup templates to have distinct/selectable identities; the current duplicate is deliberately detected.

The mock intercepts only processes launched by the audit. Real Vault tests use the Vault executable found on the host. No changes are made to chart sources.
