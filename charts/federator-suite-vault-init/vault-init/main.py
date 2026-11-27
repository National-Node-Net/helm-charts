#!/usr/bin/env python3
#
# SPDX-License-Identifier: Apache-2.0
# © Crown Copyright 2026. This work has been developed by the National Digital Twin Programme and is legally
# attributed to the UK's Department for Business, Innovation, Science and Trade (BIST) as the governing entity.

"""Cloud secret wrapper and Vault bootstrap sidecar."""

from __future__ import annotations

import base64
import json
import logging
import os
import re
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import hvac
import boto3
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from google.cloud import secretmanager

from kubernetes import client as kubernetes_client
from kubernetes import config as kubernetes_config
from kubernetes.client.rest import ApiException

LOG = logging.getLogger("vault-init")


@dataclass(frozen=True)
class Config:
    # load process configuration once when the container starts.
    aws_endpoint_url: str | None = os.getenv("AWS_ENDPOINT_URL") or None # localstack/testing only empty for real AWS
    aws_region: str = os.getenv("AWS_REGION", "eu-west-2")
    azure_keyvault_name: str = os.getenv("AZURE_VAULT_NAME", "")
    azure_keyvault_url: str = f"https://{os.getenv('AZURE_VAULT_NAME', '')}.vault.azure.net/"
    cert_secret: str = os.getenv("CERT_MANAGER_TOKEN_SECRET", "certificate-manager-vault-token")
    gcp_project: str = os.getenv("GCP_PROJECT", "")
    hostname: str = os.getenv("HOSTNAME", "vault-0")
    log_level: str = os.getenv("LOG_LEVEL", "INFO")
    namespace: str = os.getenv("NAMESPACE", "default")
    provider: str = os.getenv("CLOUD_PROVIDER", "aws")
    secret: str = os.getenv("SECRETS_MANAGER_SECRET_NAME", "")
    vault_addr: str = os.getenv("VAULT_ADDR", "http://localhost:8200").rstrip("/")
    vault_auto_unseal: bool = os.getenv("VAULT_AUTO_UNSEAL", "true").lower() == "true"
    vault_configs_path: str = os.getenv("VAULT_CONFIGS_PATH", "secret/data")
    vault_key_shares: int = int(os.getenv("VAULT_KEY_SHARES", "5"))
    vault_key_threshold: int = int(os.getenv("VAULT_KEY_THRESHOLD", "3"))
    vault_replicas: int = int(os.getenv("VAULT_REPLICAS", "1"))

config = Config()


def preflight_checks(provider: str, secret: str) -> None:
    LOG.info("Running preflight checks for [%s] before continuing.", provider)
    if provider == "aws":
        client = boto3.client("secretsmanager", region_name=config.aws_region, endpoint_url=config.aws_endpoint_url)
        try:
            result = client.get_secret_value(SecretId=secret)
            current_value = result.get("SecretString")
            if current_value is None:
                raise RuntimeError(f"AWS secret {secret} does not contain SecretString")

            # Write the existing value back unchanged to verify write permission.
            client.put_secret_value(SecretId=secret, SecretString=current_value, VersionStages=["AWSCURRENT"])
        except client.exceptions.ResourceNotFoundException:
            # create a placeholder and verify that it can also be updated. The
            # real Vault credentials replace this value after initialization.
            placeholder = "vault-init-preflight"
            client.create_secret(Name=secret, SecretString=placeholder)
            client.put_secret_value(SecretId=secret, SecretString=placeholder, VersionStages=["AWSCURRENT"])


def set_or_get_secret(provider: str, secret: str, operation: str, value: str | None = None) -> str:
    LOG.info("Handling secrets for [%s]", provider)

    # read or write the configured secret using one provider-specific path.
    if provider == "local":
        # use Kubernetes as the local credential store.
        kubernetes_config.load_incluster_config()
        kube = kubernetes_client.CoreV1Api()
        if operation == "get":
            try:
                result = kube.read_namespaced_secret(name=secret, namespace=config.namespace)
            except ApiException as exc:
                raise RuntimeError(f"Kubernetes secret {secret} returned HTTP {exc.status}") from exc
            encoded = (result.data or {}).get("vault-credentials")
            if not encoded:
                raise RuntimeError(f"vault-credentials missing in Kubernetes secret {secret}")
            return base64.b64decode(encoded, validate=True).decode()
        # store two Kubernetes Secrets: one for Vault credentials and one for the root token.
        root_token = json.loads(value or "{}").get("root_token", "")
        secrets = (
            # the full Vault bootstrap response is used when recovering Vault.
            (secret, "vault-credentials", value or ""),
            # the certificate manager only needs the Vault root token.
            (config.cert_secret, "vault-token", root_token),
        )
        for name, key, content in secrets:
            # create new Secrets and replace them when they already exist.
            body = kubernetes_client.V1Secret(
                metadata=kubernetes_client.V1ObjectMeta(name=name),
                type="Opaque",
                data={key: base64.b64encode(content.encode()).decode()},
            )
            try:
                kube.create_namespaced_secret(namespace=config.namespace, body=body)
            except ApiException as exc:
                if exc.status != 409:
                    raise
                kube.replace_namespaced_secret(name=name, namespace=config.namespace, body=body)
        return ""

    if provider == "aws":
        client = boto3.client("secretsmanager", region_name=config.aws_region, endpoint_url=config.aws_endpoint_url)
        if operation == "get":
            result = client.get_secret_value(SecretId=secret)
            if "SecretString" not in result:
                raise RuntimeError("secret has no SecretString")
            return result["SecretString"]
        client.put_secret_value(SecretId=secret, SecretString=value or "", VersionStages=["AWSCURRENT"])
        return ""

    if provider == "azure":
        # Azure uses the final path component as the Key Vault secret name.
        # dont log Azure HTTP request and response headers before using the SDK.
        logging.getLogger("azure").setLevel(logging.WARNING)
        logging.getLogger("azure.core.pipeline.policies.http_logging_policy").setLevel(logging.WARNING)
        client = SecretClient(vault_url=config.azure_keyvault_url, credential=DefaultAzureCredential())
        name = secret.strip("/").split("/")[-1]
        if operation == "get":
            result = client.get_secret(name)
            if result.value is None:
                raise RuntimeError("secret has no value")
            return result.value
        client.set_secret(name, value or "")
        return ""

    if provider == "gcp":
        # GCP reads the latest version and appends new versions on writes.
        name = f"projects/{config.gcp_project}/secrets/{secret.strip('/').split('/')[-1]}"
        client = secretmanager.SecretManagerServiceClient(transport="rest")
        if operation == "get":
            result = client.access_secret_version(request={"name": name + "/versions/latest"})
            if result.payload is None:
                raise RuntimeError("secret has no payload")
            return result.payload.data.decode("utf-8")
        client.add_secret_version(request={"parent": name, "payload": {"data": (value or "").encode("utf-8")}})
        return ""

    raise ValueError(f"unsupported provider: {provider}")


def unseal(vault: hvac.Client, vault_auto_unseal: bool, response: dict[str, Any]) -> None:
    # unseal Vault with Shamir keys or wait for cloud auto-unseal.
    # Compose uses Shamir keys; production may wait for cloud KMS auto-unseal.
    if not vault_auto_unseal:
        LOG.info("Shamir unseal enabled. Unsealing with stored keys.")
        keys = response.get("keys_base64", []) or response.get("unseal_keys_b64", [])
        if not keys:
            raise RuntimeError("Unseal keys not found in init response")
        if not vault.sys.read_seal_status().get("sealed", True):
            return
        for key in keys:
            vault.sys.submit_unseal_key(key=key)
            status = vault.sys.read_seal_status()
            if status.get("sealed") is False:
                return
        raise RuntimeError("Vault still sealed after submitting all unseal keys")
    
    LOG.info("Waiting for Vault to auto-unseal.")
    for _ in range(60):
        status = vault.sys.read_seal_status()
        if status.get("sealed") is False:
            return
        time.sleep(5)
    raise RuntimeError("Vault still sealed after 300s")


def join_peers(statefulset: str, replicas: int) -> None:
    # join each additional Vault replica to the ordinal-zero leader.
    # vault-0 must be initialized before peers can join the raft cluster.
    for index in range(1, replicas):
        address = f"http://{statefulset}-{index}.{statefulset}-internal:8200"
        peer_name = f"{statefulset}-{index}"
        LOG.info("Waiting for %s to be reachable.", peer_name)
        # phase 3: wait for each peer before requesting its Raft join.
        for attempt in range(60):
            try:
                with urllib.request.urlopen(address + "/v1/sys/health", timeout=3):
                    break
            except urllib.error.HTTPError as exc:
                # any http response means the peer is reachable; its vault state
                # is handled by the subsequent raft join request.
                LOG.info("%s is reachable (Vault returned HTTP %s).", peer_name, exc.code)
                break
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                if attempt < 59:
                    LOG.warning("%s is not reachable yet (%s); retrying in 5s (%d/60).", peer_name, exc, attempt + 1)
                    time.sleep(5)
        else:
            LOG.warning("%s not reachable after 300s. Skipping join.", peer_name)
            continue

        peer = hvac.Client(url=address, timeout=15)
        for attempt in range(60):
            try:
                peer.sys.join_raft_cluster(leader_api_addr=f"http://{statefulset}-0.{statefulset}-internal:8200")
                LOG.info("Raft join request sent to %s.", peer_name)
                break
            except Exception as exc:
                if attempt == 59:
                    LOG.warning("Raft join request to %s did not succeed after 300s; continuing.", peer_name)
                    break
                LOG.warning("Raft join request to %s is not ready (%s); retrying in 5s (%d/60).", peer_name, exc, attempt + 1)
                time.sleep(5)


def configure_engines(vault: hvac.Client) -> None:
    # ensure the required KV secret engines exist.
    # configure both KV mounts idempotently before policies and roles.
    mounts = vault.sys.list_mounted_secrets_engines()["data"]
    for mount in ("secret", "node-net"):
        if mount + "/" in mounts:
            LOG.info("KV v2 mount %s/ already present.", mount)
        else:
            vault.sys.enable_secrets_engine(backend_type="kv", path=mount, options={"version": "2"})
            LOG.info("Enabled KV v2 mount %s/.", mount)


def configure_valkey(vault: hvac.Client) -> None:
    # create or preserve the internal Valkey and Sentinel credentials.
    try:
        # read the existing credentials so reruns do not replace valid values.
        response = vault.secrets.kv.v2.read_secret_version(mount_point="secret", path="apps/valkey", raise_on_deleted_version=True)
        data = response.get("data", {}).get("data", {})
    except hvac.exceptions.InvalidPath:
        # an absent secret is treated as an empty credential set.
        data = {}

    # check if all required fields are already present in the existing data.
    fields = ("valkey_username", "valkey_password", "sentinel_username", "sentinel_password")
    if all(data.get(field) for field in fields):
        LOG.info("Internal Valkey and Sentinel credentials already exist in secret/apps/valkey.")
        return

    def generate() -> str:
        # request a password from Vault's password policy engine.
        response = vault.read("sys/policies/password/valkey-password-policy-passwordrule/generate") or {}
        password = response.get("data", {}).get("password")
        if not password:
            raise RuntimeError("Vault did not generate a Valkey password")
        return password

    # generate only missing passwords, preserving any existing password values.
    value = {
        "valkey_username": data.get("valkey_username") or "default",
        "valkey_password": data.get("valkey_password") or generate(),
        "sentinel_username": data.get("sentinel_username") or "default",
        "sentinel_password": data.get("sentinel_password") or generate(),
    }
    vault.secrets.kv.v2.create_or_update_secret(mount_point="secret", path="apps/valkey", secret=value)
    LOG.info("Created internal Valkey and Sentinel credentials in secret/apps/valkey.")


def configure_roles_and_policies(vault: hvac.Client) -> None:
    # configure Kubernetes auth and bind service accounts to Vault policies.
    # enable the auth backend before creating Kubernetes roles.
    # check whether the Kubernetes auth method is already enabled.
    auth = vault.sys.list_auth_methods()["data"]
    if "kubernetes/" not in auth:
        # enable Kubernetes auth once; repeated runs reuse the existing method.
        vault.sys.enable_auth_method(method_type="kubernetes")
        LOG.info("Enabled Kubernetes auth.")

    # load the cluster CA used by Vault when validating Kubernetes service accounts.
    with open("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", encoding="utf-8") as f:
        ca_cert = f.read()

    # point Vault at the in-cluster Kubernetes API and disable issuer validation.
    # this lets Vault validate service-account tokens issued by the cluster.
    vault.write("auth/kubernetes/config", kubernetes_host="https://kubernetes.default.svc", kubernetes_ca_cert=ca_cert, disable_iss_validation=True)

    # apply every rule, policy, and role from the configuration directory.
    for config_path in Path(config.vault_configs_path).glob("*"):
        if config_path.name.endswith("-passwordrule.hcl"):
            with open(config_path, encoding="utf-8") as f:
                LOG.info("Updating password policy %s.", config_path.stem)
                vault.write(f"sys/policies/password/{config_path.stem}", policy=f.read())
        elif config_path.name.endswith("-policy.hcl"):
            with open(config_path, encoding="utf-8") as f:
                policy = f.read()
            LOG.info("Updating policy %s.", config_path.stem)
            vault.sys.create_or_update_policy(name=config_path.stem, policy=policy)
        elif config_path.name.endswith("-role.json"):
            with open(config_path, encoding="utf-8") as f:
                role = json.load(f)
            LOG.info("Updating role %s.", config_path.stem)
            vault.auth.kubernetes.create_role(name=config_path.stem, **role)

def park() -> None:
    # keep the sidecar alive after setup completes.
    LOG.info("Parking sidecar idle to avoid restart loops.")
    while True:
        time.sleep(3600)

def initialize_or_recover(vault: hvac.Client, provider: str, secret: str, vault_key_shares: int, vault_key_threshold: int, vault_auto_unseal: bool) -> None:
    if vault.sys.is_initialized():
        LOG.info("Vault already initialized. Retrieving token from backend.")        
        credentials = json.loads(set_or_get_secret(provider, secret, "get"))
        vault.token = credentials.get("root_token", "")
        if not vault.token:
            raise RuntimeError("root_token not found in secret backend payload")
        unseal(vault, vault_auto_unseal, credentials)
        return

    # we are not initialized, run the init process to store the generated keys for the provider and unseal
    LOG.info("Vault not initialized. Running init.")
    preflight_checks(provider, secret) # ensure the secret backend is ready before initializing Vault *will throw if not ready*
    if vault_auto_unseal:
        response = vault.sys.initialize(recovery_shares=vault_key_shares, recovery_threshold=vault_key_threshold)
    else:
        response = vault.sys.initialize(secret_shares=vault_key_shares, secret_threshold=vault_key_threshold)
    vault.token = response.get("root_token", "")
    if not vault.token:
        raise RuntimeError("Init failed: root token not found")
    credentials = json.dumps(
        {
            "root_token": vault.token,
            "recovery_keys_b64": response.get("recovery_keys_base64", []),
            "unseal_keys_b64": response.get("keys_base64", []),
        },
        separators=(",", ":"),
    )
    LOG.info("Storing init credentials in secret backend (%s).", provider)

    # if this throws eg cannot put the secret, it will raise an exception which kill the process before we unseal
    set_or_get_secret(provider, secret, "put", credentials)

    # Only unseal after the generated credentials have been persisted. If
    # storage fails, the exception terminates the sidecar and Kubernetes
    # can restart it without Vault continuing with an unpersisted key set.
    unseal(vault, vault_auto_unseal, response)

def main() -> None:
    # run the Vault setup flow for the ordinal-zero instance.
    logging.basicConfig(level=config.log_level.upper(), format="[vault-setup] %(levelname)s %(message)s")
    
    vault = hvac.Client(url=config.vault_addr, timeout=15)

    match = re.search(r"-(\d+)$", config.hostname)
    if not match:
        raise RuntimeError(f"Cannot determine pod ordinal from HOSTNAME={config.hostname}")
    if match.group(1) != "0":
        LOG.info("Pod %s is not ordinal-0. Skipping setup.", config.hostname)
        park()
    if not config.secret:
        raise RuntimeError("SECRETS_MANAGER_SECRET_NAME is required")

    # phase 1 and 2: wait for Vault, then initialize or recover credentials.
    LOG.info("Phase 1 - Waiting for Vault API (%s).", config.vault_addr)
    for attempt in range(60):
        try:
            with urllib.request.urlopen(config.vault_addr + "/v1/sys/health", timeout=3):
                break
        except urllib.error.HTTPError as exc:
            if exc.code in (429, 501, 503):
                # these responses prove that vault is reachable and describe its
                # bootstrap state: 429 means standby, 501 means uninitialized,
                # and 503 means sealed. continue so the setup flow can handle it.
                break
            # unexpected vault responses, such as 403 or 500, are real failures.
            raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < 59:
                time.sleep(5)
    else:
        raise RuntimeError("Vault API unreachable after 300s")

    # phase 2: initialize or recover Vault, then join peers.
    initialize_or_recover(
        vault,
        config.provider,
        config.secret,
        config.vault_key_shares,
        config.vault_key_threshold,
        config.vault_auto_unseal,
    )

    # phase 3: join peer Vault instances.
    join_peers(config.hostname.rsplit("-", 1)[0], config.vault_replicas)
    if not (vault.auth.token.lookup_self() or {}).get("data", {}).get("id"):
        raise RuntimeError("Root token validation failed")
    
    # phase 4: configure engines, valkey, Kubernetes auth, policies, and roles.
    configure_engines(vault)

    # apply the password rule before generating Valkey credentials.
    configure_roles_and_policies(vault)
    configure_valkey(vault)
    
    LOG.info("Vault setup complete.")
    park()


if __name__ == "__main__":
    main()


# vault may briefly redirect to a stale pod ip while the statefulset or raft
# cluster is restarting; a stable vault api_addr should prevent this long term.
#
# a single 501 response must not trigger vault initialization. during startup,
# vault can briefly report that it is uninitialized before raft storage is ready.
# require several consecutive 501 responses before creating a new root token,
# otherwise the existing azure bootstrap secret could be overwritten.
