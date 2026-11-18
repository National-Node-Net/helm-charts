# Vault setup variant 2 audit

73 of 78 checks passed. This is not approval for deployment. Cloud CLIs and Kubernetes were mocked; actual Vault was used for fresh Shamir initialization, policies, KV/auth setup, repeat execution, and a sealed restart. Raft success/failure and cloud KMS auto-unseal were simulated, not live cluster tests. No source fixes were made during the audit.

## Confirmed problems

1. **Local sealed restarts fail**. The recovery branch loads the root token but never uses stored unseal keys. Real Vault returns HTTP 503 (Vault is sealed) at token lookup. This affects initialized local storage after a Vault restart; the cloud recovery branch also lacks a bounded auto-unseal wait.
2. **A failed Valkey read can cause password replacement**. `vault kv get ... || true` treats authorization/transport errors as missing credentials. The injected read-error test reaches `vault kv put` with generated replacements. Only a genuine missing-secret response should allow creation.
3. **GCP project inference fails for the documented resource name**. `projects/PROJECT/secrets/NAME` has no leading `/projects/`, so the sed expression extracts nothing. Explicit GCP_PROJECT works; its fallback does not. The normal values also contain a nonempty placeholder, so that must be replaced or removed for inference to run.
4. **Both script templates render the same Kubernetes identity**. The chart renders two ConfigMaps called `vault-setup-script` in the same namespace. A deployment must select exactly one implementation.

## Additional failure window identified by inspection

Initialization credentials exist only in shell memory until the backend write succeeds. If initialization succeeds but the write fails (or the process dies before it), the next attempt sees Vault initialized and tries to read credentials that were never stored. The current script has no durable recovery path or write retry for this window. Backend permissions/existence should be checked before initialization and persistence needs a deliberate recovery design.

## Passing coverage

- Helm render and POSIX shell syntax with static secrets and external Valkey independently enabled/disabled; policy-file keys match conditions.
- Each provider: initialization/store, initialized/read, read failure, write failure, invalid JSON, missing root token.
- Local: both Kubernetes secrets, POST-conflict/PUT path, malformed base64, missing credentials, failed second secret write.
- Ordinal skipping, missing backend/provider inputs, unreachable Vault timeout, auto-unseal timeout, invalid token, configuration error propagation.
- Existing credentials remain unchanged; individually missing Valkey/Sentinel fields preserve the other values.
- Raft peer reachability, join success, unreachable peers, failed join warning (mocked).
- Real Vault: fresh initialization and unseal, KV mounts, password generation, HCL policies, auth roles, repeat run without credential rotation.

The two sealed-restart tests (mock and real) fail for the same defect. Other failed checks are duplicate ConfigMaps, GCP inference, and unsafe Valkey read-error handling. Full per-check results are in results.json; each case directory includes output.log and calls.jsonl. Exit 77 in passing simulated setup runs is the test's idle-loop sentinel.
