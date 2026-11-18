import base64
import json
import os
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))


hvac = types.ModuleType("hvac")
hvac.Client = Mock(name="HVACClient")
hvac.exceptions = types.SimpleNamespace(InvalidPath=ValueError)
boto3 = types.ModuleType("boto3")
azure = types.ModuleType("azure")
azure_identity = types.ModuleType("azure.identity")
azure_identity.DefaultAzureCredential = Mock()
azure_keyvault = types.ModuleType("azure.keyvault")
azure_secrets = types.ModuleType("azure.keyvault.secrets")
azure_secrets.SecretClient = Mock()
google = types.ModuleType("google")
google_cloud = types.ModuleType("google.cloud")
google_secretmanager = types.ModuleType("google.cloud.secretmanager")
google_secretmanager.SecretManagerServiceClient = Mock()
kubernetes = types.ModuleType("kubernetes")
kubernetes_client = types.ModuleType("kubernetes.client")
kubernetes_client.rest = types.ModuleType("kubernetes.client.rest")
kubernetes_client.rest.ApiException = type("ApiException", (Exception,), {})
kubernetes_config = types.ModuleType("kubernetes.config")
kubernetes_config.load_incluster_config = Mock()
kubernetes.client = kubernetes_client
kubernetes.config = kubernetes_config
fake_modules = {
    "hvac": hvac,
    "boto3": boto3,
    "azure": azure,
    "azure.identity": azure_identity,
    "azure.keyvault": azure_keyvault,
    "azure.keyvault.secrets": azure_secrets,
    "google": google,
    "google.cloud": google_cloud,
    "google.cloud.secretmanager": google_secretmanager,
    "kubernetes": kubernetes,
    "kubernetes.client": kubernetes_client,
    "kubernetes.client.rest": kubernetes_client.rest,
    "kubernetes.config": kubernetes_config,
}

with patch.dict(sys.modules, fake_modules):
    import main


class ProviderTests(unittest.TestCase):
    def test_aws_read_and_write(self):
        # verify aws secret reads and writes use the expected api calls.
        client = Mock()
        client.get_secret_value.return_value = {"SecretString": "aws-value"}
        boto3 = types.SimpleNamespace(client=Mock(return_value=client))
        with patch.object(main, "boto3", boto3), patch.dict(os.environ, {"AWS_REGION": "eu-west-2"}, clear=False):
            self.assertEqual(main.set_or_get_secret("aws", "secret", "get"), "aws-value")
            main.set_or_get_secret("aws", "secret", "put", "new-value")
        client.get_secret_value.assert_called_once_with(SecretId="secret")
        client.put_secret_value.assert_called_once_with(
            SecretId="secret", SecretString="new-value", VersionStages=["AWSCURRENT"]
        )

    def test_azure_read_and_write(self):
        # verify azure secret names are normalized before access.
        client = Mock()
        client.get_secret.return_value.value = "azure-value"
        with patch.object(main, "SecretClient", Mock(return_value=client)), patch.dict(
            os.environ, {"AZURE_VAULT_NAME": "vault"}, clear=False
        ):
            self.assertEqual(main.set_or_get_secret("azure", "/path/secret", "get"), "azure-value")
            main.set_or_get_secret("azure", "/path/secret", "put", "new-value")
        client.get_secret.assert_called_once_with("secret")
        client.set_secret.assert_called_once_with("secret", "new-value")

    def test_gcp_read_and_write(self):
        # verify gcp payloads are read and new versions are written.
        client = Mock()
        client.access_secret_version.return_value.payload.data = b"gcp-value"
        with patch.object(
            main, "secretmanager", types.SimpleNamespace(SecretManagerServiceClient=Mock(return_value=client))
        ), patch.dict(os.environ, {"GCP_PROJECT": "project"}, clear=False):
            self.assertEqual(main.set_or_get_secret("gcp", "/path/secret", "get"), "gcp-value")
            main.set_or_get_secret("gcp", "/path/secret", "put", "new-value")
        client.access_secret_version.assert_called_once()
        client.add_secret_version.assert_called_once()

    def test_unsupported_provider(self):
        # reject providers that are not configured by the application.
        with self.assertRaisesRegex(ValueError, "unsupported provider"):
            main.set_or_get_secret("unknown", "secret", "get")
        with self.assertRaisesRegex(ValueError, "unsupported provider"):
            main.set_or_get_secret("unknown", "secret", "put", "value")

    def test_aws_read_requires_secret_string(self):
        # report an error when aws returns no secret string.
        client = Mock()
        client.get_secret_value.return_value = {}
        with patch.object(main, "boto3", types.SimpleNamespace(client=Mock(return_value=client))):
            with self.assertRaisesRegex(RuntimeError, "no SecretString"):
                main.set_or_get_secret("aws", "secret", "get")

    def test_azure_read_requires_value(self):
        # report an error when azure returns an empty secret value.
        client = Mock()
        client.get_secret.return_value.value = None
        with patch.object(main, "SecretClient", Mock(return_value=client)):
            with self.assertRaisesRegex(RuntimeError, "no value"):
                main.set_or_get_secret("azure", "secret", "get")

    def test_gcp_read_requires_payload(self):
        # report an error when gcp returns no payload.
        client = Mock()
        client.access_secret_version.return_value.payload = None
        with patch.object(main, "secretmanager", types.SimpleNamespace(SecretManagerServiceClient=Mock(return_value=client))):
            with self.assertRaisesRegex(RuntimeError, "no payload"):
                main.set_or_get_secret("gcp", "secret", "get")


class VaultFlowTests(unittest.TestCase):
    def test_local_credentials_read_and_write(self):
        # verify local credentials are read and stored as kubernetes secrets.
        kube = Mock()
        credentials = base64.b64encode(json.dumps({"root_token": "test-token"}).encode()).decode()
        kube.request.return_value = (200, {"data": {"vault-credentials": credentials}})
        result = types.SimpleNamespace(data={"vault-credentials": credentials})
        kube.read_namespaced_secret.return_value = result
        fake_client = types.SimpleNamespace(CoreV1Api=Mock(return_value=kube), V1Secret=lambda **kwargs: kwargs, V1ObjectMeta=lambda **kwargs: kwargs)
        with patch.object(main, "kubernetes_client", fake_client), patch.object(main.kubernetes_config, "load_incluster_config"):
            self.assertEqual(
                json.loads(main.set_or_get_secret("local", "credentials", "get"))["root_token"], "test-token"
            )
            main.set_or_get_secret("local", "credentials", "put", '{"root_token":"test-token"}')
        self.assertEqual(kube.create_namespaced_secret.call_count, 2)

    def test_local_credentials_replaces_existing_secrets(self):
        # verify existing kubernetes secrets are replaced after a conflict.
        kube = Mock()
        conflict = main.ApiException()
        conflict.status = 409
        kube.create_namespaced_secret.side_effect = [conflict, conflict]
        fake_client = types.SimpleNamespace(CoreV1Api=Mock(return_value=kube), V1Secret=lambda **kwargs: kwargs, V1ObjectMeta=lambda **kwargs: kwargs)
        with patch.object(main, "kubernetes_client", fake_client), patch.object(main.kubernetes_config, "load_incluster_config"):
            main.set_or_get_secret("local", "credentials", "put", '{"root_token":"test-token"}')
        self.assertEqual(kube.replace_namespaced_secret.call_count, 2)

    def test_local_credentials_reports_api_error(self):
        # convert kubernetes api failures into a clear runtime error.
        kube = Mock()
        error = main.ApiException()
        error.status = 500
        kube.read_namespaced_secret.side_effect = error
        fake_client = types.SimpleNamespace(CoreV1Api=Mock(return_value=kube))
        with patch.object(main, "kubernetes_client", fake_client), patch.object(main.kubernetes_config, "load_incluster_config"):
            with self.assertRaisesRegex(RuntimeError, "HTTP 500"):
                main.set_or_get_secret("local", "credentials", "get")

    def test_local_credentials_requires_stored_value(self):
        # reject a kubernetes secret that lacks stored credentials.
        kube = Mock()
        kube.read_namespaced_secret.return_value = types.SimpleNamespace(data={})
        fake_client = types.SimpleNamespace(CoreV1Api=Mock(return_value=kube))
        with patch.object(main, "kubernetes_client", fake_client), patch.object(main.kubernetes_config, "load_incluster_config"):
            with self.assertRaisesRegex(RuntimeError, "missing in Kubernetes secret"):
                main.set_or_get_secret("local", "credentials", "get")

    def test_shamir_unseal_uses_stored_keys(self):
        # verify shamir unseal submits the stored key.
        vault = Mock()
        vault.sys.read_seal_status.side_effect = [{"sealed": True}, {"sealed": False}]
        main.unseal(vault, False, {"unseal_keys_b64": ["key"]})
        vault.sys.submit_unseal_key.assert_called_once_with(key="key")

    def test_shamir_unseal_requires_keys(self):
        # reject a shamir initialization response without unseal keys.
        with self.assertRaisesRegex(RuntimeError, "Unseal keys not found"):
            main.unseal(Mock(), False, {})

    def test_shamir_unseal_skips_already_unsealed_vault(self):
        # avoid submitting keys when vault is already unsealed.
        vault = Mock()
        vault.sys.read_seal_status.return_value = {"sealed": False}
        main.unseal(vault, False, {"unseal_keys_b64": ["key"]})
        vault.sys.submit_unseal_key.assert_not_called()

    def test_auto_unseal_times_out(self):
        # fail when automatic unsealing never clears the sealed state.
        vault = Mock()
        vault.sys.read_seal_status.return_value = {"sealed": True}
        with patch.object(main.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "still sealed"):
                main.unseal(vault, True, {})

    def test_shamir_unseal_stops_after_threshold(self):
        # stop shamir key submission once vault reports unsealed.
        vault = Mock()
        vault.sys.read_seal_status.side_effect = [{"sealed": True}, {"sealed": True}, {"sealed": False}]
        main.unseal(vault, False, {"unseal_keys_b64": ["one", "two"]})
        self.assertEqual(vault.sys.submit_unseal_key.call_count, 2)

    def test_shamir_unseal_fails_when_keys_are_exhausted(self):
        # fail when every supplied key is rejected and vault remains sealed.
        vault = Mock()
        vault.sys.read_seal_status.side_effect = [{"sealed": True}, {"sealed": True}]
        with self.assertRaisesRegex(RuntimeError, "still sealed"):
            main.unseal(vault, False, {"unseal_keys_b64": ["key"]})

    def test_auto_unseal_waits_until_unsealed(self):
        # poll automatic unseal until vault becomes available.
        vault = Mock()
        vault.sys.read_seal_status.side_effect = [{"sealed": True}, {"sealed": False}]
        with patch.object(main.time, "sleep"):
            main.unseal(vault, True, {})
        self.assertEqual(vault.sys.read_seal_status.call_count, 2)

    def test_engines_and_kubernetes_roles(self):
        # configure the kv engine, kubernetes auth, policies, and roles.
        vault = Mock()
        vault.sys.list_mounted_secrets_engines.return_value = {"data": {"secret/": {}}}
        vault.sys.list_auth_methods.return_value = {"data": {}}
        policy_files = [
            types.SimpleNamespace(name="certificate-manager-policy.hcl", stem="certificate-manager-policy"),
            types.SimpleNamespace(name="client-server-vault-reader-policy.hcl", stem="client-server-vault-reader-policy"),
            types.SimpleNamespace(name="certificate-manager-role.json", stem="certificate-manager-role"),
            types.SimpleNamespace(name="client-server-vault-reader-role.json", stem="client-server-vault-reader-role"),
            types.SimpleNamespace(name="valkey-password-policy-passwordrule.hcl", stem="valkey-password-policy-passwordrule"),
        ]
        scripts = Mock()
        scripts.glob.return_value = policy_files
        with patch.object(main, "open", unittest.mock.mock_open(read_data="policy")), patch.object(
            main.json, "load", return_value={"policies": ["certificate-manager-policy"]}
        ), patch.object(main, "Path", return_value=scripts):
            main.configure_engines(vault)
            main.configure_roles_and_policies(vault)
        vault.sys.enable_secrets_engine.assert_called_once_with(
            backend_type="kv", path="node-net", options={"version": "2"}
        )
        vault.sys.enable_auth_method.assert_called_once_with(method_type="kubernetes")
        self.assertEqual(vault.auth.kubernetes.create_role.call_count, 2)
        self.assertEqual(vault.sys.create_or_update_policy.call_count, 2)

    def test_engines_are_unchanged_when_already_configured(self):
        # do not recreate an existing kv engine.
        vault = Mock()
        vault.sys.list_mounted_secrets_engines.return_value = {"data": {"secret/": {}, "node-net/": {}}}
        main.configure_engines(vault)
        vault.sys.enable_secrets_engine.assert_not_called()

    def test_roles_do_not_reenable_existing_auth(self):
        # do not re-enable kubernetes auth when it already exists.
        vault = Mock()
        vault.sys.list_auth_methods.return_value = {"data": {"kubernetes/": {}}}
        scripts = Mock()
        scripts.glob.return_value = []
        with patch.object(main, "open", unittest.mock.mock_open(read_data="ca")), patch.object(main, "Path", return_value=scripts):
            main.configure_roles_and_policies(vault)
        vault.sys.enable_auth_method.assert_not_called()

    def test_roles_and_policies_apply_password_rule(self):
        # write password rules through the sys endpoint instead of policies.
        vault = Mock()
        vault.sys.list_auth_methods.return_value = {"data": {"kubernetes/": {}}}
        scripts = Mock()
        scripts.glob.return_value = [
            types.SimpleNamespace(name="valkey-password-policy-passwordrule.hcl", stem="valkey-password-policy-passwordrule")
        ]
        with patch.object(main, "open", unittest.mock.mock_open(read_data="policy")), patch.object(main, "Path", return_value=scripts):
            main.configure_roles_and_policies(vault)
        vault.sys.create_or_update_policy.assert_not_called()
        vault.auth.kubernetes.create_role.assert_not_called()
        self.assertIn(
            unittest.mock.call("sys/policies/password/valkey-password-policy-passwordrule", policy="policy"),
            vault.write.call_args_list,
        )

    def test_configure_valkey_preserves_existing_credentials(self):
        # preserve all existing valkey credentials without generating new ones.
        vault = Mock()
        vault.secrets.kv.v2.read_secret_version.return_value = {
            "data": {"data": {
                "valkey_username": "user",
                "valkey_password": "password",
                "sentinel_username": "sentinel",
                "sentinel_password": "sentinel-password",
            }}
        }
        with patch.object(main, "open", unittest.mock.mock_open(read_data="policy")):
            main.configure_valkey(vault)
        vault.read.assert_not_called()
        vault.secrets.kv.v2.create_or_update_secret.assert_not_called()

    def test_configure_valkey_generates_missing_passwords(self):
        # generate only the missing valkey and sentinel passwords.
        vault = Mock()
        vault.secrets.kv.v2.read_secret_version.side_effect = ValueError
        vault.read.side_effect = [
            {"data": {"password": "password"}},
            {"data": {"password": "sentinel-password"}},
        ]
        with patch.object(main, "open", unittest.mock.mock_open(read_data="policy")):
            main.configure_valkey(vault)
        value = vault.secrets.kv.v2.create_or_update_secret.call_args.kwargs["secret"]
        self.assertEqual(value["valkey_username"], "default")
        self.assertEqual(value["sentinel_username"], "default")
        self.assertEqual(value["valkey_password"], "password")
        self.assertEqual(value["sentinel_password"], "sentinel-password")
        self.assertEqual(
            vault.read.call_args_list,
            [
                unittest.mock.call("sys/policies/password/valkey-password-policy-passwordrule/generate"),
                unittest.mock.call("sys/policies/password/valkey-password-policy-passwordrule/generate"),
            ],
        )

    def test_configure_valkey_fails_when_password_generation_returns_empty(self):
        # fail when vault returns an empty generated password.
        vault = Mock()
        vault.secrets.kv.v2.read_secret_version.side_effect = ValueError
        vault.read.return_value = {"data": {"password": ""}}
        with patch.object(main, "open", unittest.mock.mock_open(read_data="policy")):
            with self.assertRaisesRegex(RuntimeError, "did not generate"):
                main.configure_valkey(vault)

    def test_configure_valkey_fails_when_password_generation_returns_none(self):
        # fail when vault returns no generated password response.
        vault = Mock()
        vault.secrets.kv.v2.read_secret_version.side_effect = ValueError
        vault.read.return_value = None
        with self.assertRaisesRegex(RuntimeError, "did not generate"):
            main.configure_valkey(vault)

    def test_join_peers_sends_join_request(self):
        # join a raft peer after confirming that it is reachable.
        peer = Mock()
        with patch.object(main.urllib.request, "urlopen") as urlopen, patch.object(main.hvac, "Client", return_value=peer):
            main.join_peers("vault", 2)
        urlopen.assert_called_once()
        peer.sys.join_raft_cluster.assert_called_once_with(leader_api_addr="http://vault-0.vault-internal:8200")

    def test_join_peers_skips_unreachable_peer(self):
        # skip raft joining when the peer remains unreachable.
        with patch.object(main.urllib.request, "urlopen", side_effect=main.urllib.error.URLError("offline")), patch.object(main.time, "sleep"):
            with patch.object(main.hvac, "Client") as client:
                main.join_peers("vault", 2)
        client.assert_not_called()

    def test_join_peers_skips_single_replica(self):
        # do not contact peers when Vault has only one replica.
        with patch.object(main.urllib.request, "urlopen") as urlopen, patch.object(main.hvac, "Client") as client:
            main.join_peers("vault", 1)
        urlopen.assert_not_called()
        client.assert_not_called()

    def test_initialize_new_vault_stores_credentials(self):
        # initialize a new vault and persist its bootstrap credentials.
        vault = Mock()
        vault.sys.is_initialized.return_value = False
        vault.sys.initialize.return_value = {
            "root_token": "root",
            "keys_base64": ["key"],
            "recovery_keys_base64": [],
        }
        with patch.object(main, "unseal") as unseal, patch.object(main, "set_or_get_secret") as store:
            main.initialize_or_recover(vault, "test", "secret", 5, 3, False)
        vault.sys.initialize.assert_called_once_with(secret_shares=5, secret_threshold=3)
        unseal.assert_called_once()
        store.assert_called_once()

    def test_recover_existing_vault_reads_and_unseals(self):
        # recover stored credentials and unseal an existing vault.
        vault = Mock()
        vault.sys.is_initialized.return_value = True
        with patch.object(main, "set_or_get_secret", return_value='{"root_token":"root"}') as read, patch.object(main, "unseal") as unseal:
            main.initialize_or_recover(vault, "test", "secret", 5, 3, True)
        read.assert_called_once_with("test", "secret", "get")
        unseal.assert_called_once()
        self.assertEqual(vault.token, "root")

    def test_initialize_requires_root_token(self):
        # fail initialization when vault does not return a root token.
        vault = Mock()
        vault.sys.is_initialized.return_value = False
        vault.sys.initialize.return_value = {"keys_base64": ["key"]}
        with self.assertRaisesRegex(RuntimeError, "root token"):
            main.initialize_or_recover(vault, "test", "secret", 5, 3, False)

    def test_recover_requires_root_token(self):
        # fail recovery when stored credentials lack a root token.
        vault = Mock()
        vault.sys.is_initialized.return_value = True
        with patch.object(main, "set_or_get_secret", return_value="{}"):
            with self.assertRaisesRegex(RuntimeError, "root_token not found"):
                main.initialize_or_recover(vault, "test", "secret", 5, 3, True)


if __name__ == "__main__":
    unittest.main()
