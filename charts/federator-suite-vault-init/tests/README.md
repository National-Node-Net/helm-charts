From the Vault-init project directory, use the test runner for the unit tests:

```sh
cd charts/federator-suite-vault-init
./scripts/run-tests.sh
```

The test runner uses the local `uv` environment when available. Use
`./scripts/run-tests.sh --docker` to run the same unit tests in the Docker test stage.
