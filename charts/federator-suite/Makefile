# Federator Suite Helm Chart Makefile

.PHONY: help
help: ## Show this help message
	@echo "Federator Suite"
	@echo "==============="
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  ENV                  environment: local, dev, or prod (default: local)"
	@echo "  ORG                  organisation values file (default: bcc)"
	@echo "  RELEASE_NAME         helm release name (default: federator-suite)"
	@echo "  NAMESPACE            kubernetes namespace derived from the org values file"
	@echo "  RUNTIME_SECRETS_FILE local vault json (default: values/overrides/local/<org>.secrets.json)"
	@echo "  TYPE                 image registry type for image_pull_secrets (default: aws)"
	@echo "  CREDS                registry credentials json for image_pull_secrets"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy-local ENV=local ORG=bcc"
	@echo "  make image_pull_secrets ENV=local ORG=bcc TYPE=aws CREDS='{\"AWS_PROFILE\":\"dev\",\"AWS_REGION\":\"eu-west-2\"}'"
	@echo "  make bootstrap_runtime_secrets ENV=local ORG=bcc"
	@echo "  make validate ENV=local ORG=bcc"
	@echo "  make status ENV=local ORG=bcc"
	@echo "  make healthcheck ENV=local ORG=bcc"
	@echo "  make logs-client ENV=local ORG=bcc"
	@echo "  make port-forward-all ENV=local ORG=bcc"
	@echo "  make deploy ENV=dev ORG=bcc"
	@echo "  make upgrade ENV=dev ORG=bcc"
	@echo "  make uninstall-keep-data ENV=local ORG=bcc"
	@echo "  make destroy-cluster ENV=local"

# ============================================
# Configuration
# ============================================

ENV ?= local
RELEASE_NAME ?= federator-suite
ORG ?= bcc
CHART_PATH = .
MAKESCRIPTS = scripts/make
TYPE ?= aws
CREDS ?=

COMPONENT_VALUES = -f values/common-values.yaml -f values/kafka.yaml -f values/valkey.yaml -f values/vault.yaml -f values/certificate-manager.yaml -f values/opa.yaml -f values/federator.yaml -f values/valkey-ui.yaml -f values/istio.yaml

ifeq ($(ENV),local)
VALUES_FILES = $(COMPONENT_VALUES) -f values/overrides/local/local.yaml -f values/overrides/local/$(ORG).yaml
RUNTIME_SECRETS_FILE ?= values/overrides/local/$(ORG).secrets.json
NAMESPACE ?= $(shell grep 'namespace:' values/overrides/local/$(ORG).yaml 2>/dev/null | head -1 | awk '{print $$2}' || echo "ia-federation")
else ifeq ($(ENV),dev)
VALUES_FILES = $(COMPONENT_VALUES) -f values/overrides/dev/$(ORG).yaml
SECRETS_FILE = values/overrides/dev/secrets/$(ORG)-secrets.yaml
NAMESPACE ?= $(shell grep 'namespace:' values/overrides/dev/$(ORG).yaml 2>/dev/null | head -1 | awk '{print $$2}' || echo "helm-ia-federation")
else ifeq ($(ENV),prod)
VALUES_FILES = $(COMPONENT_VALUES) -f values/overrides/prod/$(ORG).yaml
SECRETS_FILE = values/overrides/prod/secrets/$(ORG)-secrets.yaml
NAMESPACE ?= $(shell grep 'namespace:' values/overrides/prod/$(ORG).yaml 2>/dev/null | head -1 | awk '{print $$2}' || echo "ia-federation")
else
$(error Unknown environment: $(ENV). Valid: local, dev, prod)
endif

ifneq (,$(wildcard $(SECRETS_FILE)))
VALUES_FILES += -f $(SECRETS_FILE)
endif

# ============================================
# Deploy
# ============================================

.PHONY: deploy
deploy: ## Deploy federator suite (ENV=local|dev|prod ORG=bcc|env|heg)
	@echo "==> Deploying to $(ENV) (ORG=$(ORG), NS=$(NAMESPACE))..."
	@$(MAKE) pre-deploy-check
	@$(MAKE) setup_cluster
	@$(MAKE) build_deps
	@$(MAKE) install_strimzio
	@$(MAKE) install_vault_secrets_operator
	@$(MAKE) _istio-inject-if-enabled
	@echo "==> Installing chart..."
ifeq ($(ENV),local)
	@# Do not use Helm --wait here: the applications require the Secret which is
	@# created only after the local Vault bootstrap below.
	@helm upgrade --install $(RELEASE_NAME) $(CHART_PATH) -n $(NAMESPACE) $(VALUES_FILES) --timeout 10m
	@# The bootstrap waits for Vault, writes the org.secrets JSON, then VSO creates the
	@# federator-runtime-properties Kubernetes Secret.
	@$(MAKE) bootstrap_runtime_secrets
	@echo "==> Waiting for federator-runtime-properties..."
	@kubectl wait -n $(NAMESPACE) --for=condition=Ready vaultstaticsecret/federator-runtime-properties --timeout=10m
	@echo "==> Waiting for applications..."
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-federator-server --timeout=10m
	@kubectl rollout status -n $(NAMESPACE) deployment/$(RELEASE_NAME)-federator-client --timeout=10m
else
	@helm upgrade --install $(RELEASE_NAME) $(CHART_PATH) -n $(NAMESPACE) $(VALUES_FILES) --wait --timeout 10m
endif
	@$(MAKE) _verify
	@echo "==> ✓ Deployment complete!"

.PHONY: deploy-local
deploy-local: ENV=local
deploy-local: ## Deploy to local Kind cluster (ORG=bcc|env|heg)
	@$(MAKE) deploy

.PHONY: upgrade
upgrade: ## Fast helm upgrade without checks (for iterative dev)
	@echo "==> Upgrading $(RELEASE_NAME) in $(NAMESPACE) ($(ENV)/$(ORG))..."
	@kubectl delete configmap federator-server-properties federator-client-properties -n $(NAMESPACE) 2>/dev/null || true
	@helm upgrade $(RELEASE_NAME) $(CHART_PATH) -n $(NAMESPACE) $(VALUES_FILES)
	@echo "==> ✓ Upgrade complete!"

# ============================================
# Internal Targets
# ============================================

.PHONY: setup_cluster
setup_cluster:
ifeq ($(ENV),local)
	@echo "==> Cluster setup (local)..."
	@if kind get clusters | grep -q federator-suite-kind-cluster; then \
echo "  ✓ Kind cluster exists"; \
else \
echo "  → Creating Kind cluster..."; \
kind create cluster --name federator-suite-kind-cluster --config kind-config.yaml; \
fi
	@kubectl config use-context kind-federator-suite-kind-cluster
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl label namespace $(NAMESPACE) istio-injection=enabled --overwrite || true
else
	@echo "==> Verifying cluster..."
	@kubectl cluster-info > /dev/null
	@kubectl get namespace $(NAMESPACE) > /dev/null 2>&1 || (echo "ERROR: Namespace $(NAMESPACE) does not exist!" && exit 1)
	@echo "  ✓ Connected to $(ENV), namespace $(NAMESPACE) exists"
endif

.PHONY: build_deps
build_deps:
	@bash $(MAKESCRIPTS)/build_deps.sh

.PHONY: install_strimzio
install_strimzio: ## Install or verify the Strimzi prerequisite when bundled Kafka is enabled
	@# Only install Strimzi when the resolved chart creates bundled Kafka resources.
	@if helm template $(RELEASE_NAME) $(CHART_PATH) -n $(NAMESPACE) $(VALUES_FILES) 2>/dev/null | grep -q 'apiVersion: kafka.strimzi.io/v1'; then \
		bash $(MAKESCRIPTS)/install_strimzio.sh; \
	else \
		echo "==> External Kafka configured; skipping Strimzi installation"; \
	fi

.PHONY: install_vault_secrets_operator
install_vault_secrets_operator: ## Install or verify the Vault Secrets Operator prerequisite
	@bash $(MAKESCRIPTS)/install_vault_secrets_operator.sh

.PHONY: image_pull_secrets
image_pull_secrets: ## Create or refresh a registry image-pull Secret
	@bash $(MAKESCRIPTS)/image_pull_secrets.sh "$(NAMESPACE)" "$(TYPE)" '$(CREDS)'

.PHONY: bootstrap_runtime_secrets
bootstrap_runtime_secrets: ## Write local org secrets JSON to Vault for federator-runtime-properties
	@bash $(MAKESCRIPTS)/bootstrap_runtime_secrets.sh "$(NAMESPACE)" "$(RELEASE_NAME)" "$(RUNTIME_SECRETS_FILE)"

.PHONY: _istio-inject-if-enabled
_istio-inject-if-enabled:
	@ISTIO_ENABLED=$$(helm template $(RELEASE_NAME) $(CHART_PATH) -n $(NAMESPACE) $(VALUES_FILES) 2>/dev/null | \
	grep -B2 "kind: Gateway" | grep -q "networking.istio.io" && echo "true" || echo "false"); \
	if [ "$$ISTIO_ENABLED" = "true" ]; then \
	kubectl label namespace $(NAMESPACE) istio-injection=enabled --overwrite 2>/dev/null || true; \
	echo "  ✓ Istio injection enabled"; \
	fi

.PHONY: _verify
_verify:
	@echo ""
	@echo "Pods:"
	@kubectl get pods -n $(NAMESPACE)
	@echo ""
	@echo "Services:"
	@kubectl get svc -n $(NAMESPACE)

# ============================================
# Validation & Testing
# ============================================

.PHONY: validate
validate: ## Validate configuration before deployment
	@echo "==> Validating ($(ENV)/$(ORG)/$(NAMESPACE))..."
	@test -f values/common-values.yaml || (echo "ERROR: values/common-values.yaml not found" && exit 1)
	@test -f values/kafka.yaml || (echo "ERROR: values/kafka.yaml not found" && exit 1)
	@test -f values/valkey.yaml || (echo "ERROR: values/valkey.yaml not found" && exit 1)
	@test -f values/vault.yaml || (echo "ERROR: values/vault.yaml not found" && exit 1)
	@test -f values/certificate-manager.yaml || (echo "ERROR: values/certificate-manager.yaml not found" && exit 1)
	@test -f values/opa.yaml || (echo "ERROR: values/opa.yaml not found" && exit 1)
	@test -f values/federator.yaml || (echo "ERROR: values/federator.yaml not found" && exit 1)
ifeq ($(ENV),local)
	@test -f values/overrides/local/local.yaml || (echo "ERROR: values/overrides/local/local.yaml not found" && exit 1)
	@test -f values/overrides/local/$(ORG).yaml || (echo "ERROR: values/overrides/local/$(ORG).yaml not found" && exit 1)
	@test -f $(RUNTIME_SECRETS_FILE) || (echo "ERROR: $(RUNTIME_SECRETS_FILE) not found" && exit 1)
else
	@test -f values/overrides/$(ENV)/$(ORG).yaml || (echo "ERROR: values/overrides/$(ENV)/$(ORG).yaml not found" && exit 1)
	@test -f $(SECRETS_FILE) || (echo "ERROR: $(SECRETS_FILE) not found" && exit 1)
endif
	@echo "  ✓ Required files present"
	@helm lint $(CHART_PATH) $(VALUES_FILES) 2>&1 | tail -1
	@echo "  ✓ Validation passed"

.PHONY: check-cluster
check-cluster: ## Check cluster connectivity
	@echo "==> Cluster check..."
ifeq ($(ENV),local)
	@if kubectl cluster-info 2>/dev/null | head -3; then \
		echo ""; \
		echo "Context: $$(kubectl config current-context 2>/dev/null || echo '(none)')"; \
		kubectl get namespace $(NAMESPACE) 2>/dev/null || echo "  ⚠ Namespace $(NAMESPACE) does not exist (will be created)"; \
	else \
		echo "  ⚠ No cluster found — will be created by setup_cluster"; \
	fi
else
	@kubectl cluster-info | head -3
	@echo ""
	@echo "Context: $$(kubectl config current-context)"
	@kubectl get namespace $(NAMESPACE) 2>/dev/null || echo "  ⚠ Namespace $(NAMESPACE) does not exist"
	@echo ""
	@kubectl get nodes
endif

.PHONY: check-secrets
check-secrets: ## Verify secrets file exists
	@if [ "$(ENV)" = local ]; then \
		test -f "$(RUNTIME_SECRETS_FILE)" || (echo "ERROR: $(RUNTIME_SECRETS_FILE) not found" && exit 1); \
		jq -e 'type == "object"' "$(RUNTIME_SECRETS_FILE)" >/dev/null || (echo "ERROR: $(RUNTIME_SECRETS_FILE) must be a JSON object" && exit 1); \
		echo "  ✓ Runtime secrets JSON is ready for Vault bootstrap"; \
	else \
		echo "==> Checking: $(SECRETS_FILE)"; \
		test -f "$(SECRETS_FILE)" || (echo "ERROR: Secrets file not found" && exit 1); \
		grep -q "truststoreJks:" "$(SECRETS_FILE)" || echo "  ⚠ truststoreJks not found"; \
		grep -q "serverKeystoreJks:" "$(SECRETS_FILE)" || echo "  ⚠ serverKeystoreJks not found"; \
		grep -q "clientKeystoreJks:" "$(SECRETS_FILE)" || echo "  ⚠ clientKeystoreJks not found"; \
		echo "  ✓ Secrets check complete"; \
	fi

.PHONY: pre-deploy-check
pre-deploy-check: validate check-cluster check-secrets ## Run all pre-deployment checks
	@echo "==> ✓ Pre-deploy checks passed"

.PHONY: test
test: test-render lint ## Run all tests

.PHONY: test-render
test-render: ## Test template rendering
	@echo "==> Rendering templates..."
	@helm template test-$(ORG) $(CHART_PATH) $(VALUES_FILES) --namespace $(NAMESPACE) --debug 2>&1 | head -50
	@echo "==> ✓ Render successful"

.PHONY: lint
lint: ## Helm lint
	@helm lint $(CHART_PATH) $(VALUES_FILES)

.PHONY: template
template: ## Render full manifests to stdout
	@helm template $(RELEASE_NAME) $(CHART_PATH) -n $(NAMESPACE) $(VALUES_FILES)

.PHONY: debug
debug: ## Show resolved values and rendered templates
	@echo "ENV=$(ENV) ORG=$(ORG) NS=$(NAMESPACE) RELEASE=$(RELEASE_NAME)"
	@echo "VALUES: $(VALUES_FILES)"
	@echo ""
	@helm template $(RELEASE_NAME) $(CHART_PATH) -n $(NAMESPACE) $(VALUES_FILES) --debug

# ============================================
# Status & Health
# ============================================

.PHONY: status
status: ## Show status of all resources in the namespace
	@echo "==> Status: $(RELEASE_NAME) in $(NAMESPACE)"
	@echo ""
	@echo "Pods:"
	@kubectl get pods -n $(NAMESPACE) -o wide
	@echo ""
	@echo "Services:"
	@kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "PVCs:"
	@kubectl get pvc -n $(NAMESPACE) 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "Jobs:"
	@kubectl get jobs -n $(NAMESPACE) 2>/dev/null || echo "  (none)"

.PHONY: healthcheck
healthcheck: ## Check all pods are running and error-free
	@bash $(MAKESCRIPTS)/healthcheck.sh "$(NAMESPACE)" "$(RELEASE_NAME)"

# ============================================
# Logs
# ============================================

.PHONY: logs-server
logs-server: ## View federator-server logs
	@kubectl logs -l app=federator-server -n $(NAMESPACE) --tail=100 -c federator-server -f

.PHONY: logs-client
logs-client: ## View federator-client logs
	@kubectl logs -l app=federator-client -n $(NAMESPACE) --tail=100 -c federator-client -f

.PHONY: logs-opa
logs-opa: ## View OPA logs
	@kubectl logs -l app=opa -n $(NAMESPACE) --tail=100 -f

.PHONY: logs
logs: ## Show last 50 lines from all pods
	@for pod in $$(kubectl get pods -n $(NAMESPACE) -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do \
		echo "━━━ $$pod ━━━"; \
		kubectl logs $$pod -n $(NAMESPACE) --tail=50 --all-containers 2>/dev/null || echo "  (no logs)"; \
		echo ""; \
	done

# ============================================
# Port Forwarding
# ============================================

.PHONY: port-forward-all
port-forward-all: ## Forward Kafka UI (8088), Valkey UI (5540), JobRunr (8085), Vault UI (8200), OPA (8181)
	@bash $(MAKESCRIPTS)/portforward.sh "$(NAMESPACE)" "$(RELEASE_NAME)" start

.PHONY: stop-port-forwards
stop-port-forwards: ## Stop all port forwards
	@bash $(MAKESCRIPTS)/portforward.sh "$(NAMESPACE)" "$(RELEASE_NAME)" stop

.PHONY: port-forward-status
port-forward-status: ## Show active port forwards
	@bash $(MAKESCRIPTS)/portforward.sh "$(NAMESPACE)" "$(RELEASE_NAME)" status

# ============================================
# Istio
# ============================================

.PHONY: istio-enable
istio-enable: ## Enable Istio injection on namespace
	@kubectl label namespace $(NAMESPACE) istio-injection=enabled --overwrite
	@echo "✓ Istio injection enabled. Restart pods: kubectl rollout restart deployment -n $(NAMESPACE)"

.PHONY: istio-disable
istio-disable: ## Disable Istio injection on namespace
	@kubectl label namespace $(NAMESPACE) istio-injection-
	@echo "✓ Istio injection removed. Restart pods: kubectl rollout restart deployment -n $(NAMESPACE)"

.PHONY: istio-status
istio-status: ## Check Istio status
	@echo "Injection label: $$(kubectl get namespace $(NAMESPACE) -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo '(not set)')"
	@echo ""
	@echo "Istio sidecars:"
	@kubectl get pods -n $(NAMESPACE) -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.name}{" "}{end}{"\n"}{end}' | grep istio-proxy || echo "  None"
	@echo ""
	@echo "Istio resources:"
	@kubectl get gateway,virtualservice,destinationrule,peerauthentication,authorizationpolicy -n $(NAMESPACE) 2>/dev/null || echo "  None"

# ============================================
# Certificates
# ============================================

.PHONY: generate-certs
generate-certs: ## Generate local mTLS certificates (ORG=org1)
	@./scripts/generate-certs.sh $(ORG)

# ============================================
# Vault Operations
# ============================================

.PHONY: init-vault
init-vault: ## Initialize Vault and create cert-manager token secret (local only)
	@bash $(MAKESCRIPTS)/init_vault.sh "$(ENV)" "$(NAMESPACE)" "$(RELEASE_NAME)"

# ============================================
# Cleanup
# ============================================

.PHONY: uninstall
uninstall: ## Uninstall release and delete PVCs
	@echo "==> Uninstalling $(RELEASE_NAME) from $(NAMESPACE)..."
	@helm uninstall $(RELEASE_NAME) -n $(NAMESPACE) --wait
	@kubectl delete pvc -l app.kubernetes.io/instance=$(RELEASE_NAME) -n $(NAMESPACE) 2>/dev/null || true
	@echo "==> ✓ Uninstalled"

.PHONY: uninstall-keep-data
uninstall-keep-data: ## Uninstall release but keep PVCs
	@helm uninstall $(RELEASE_NAME) -n $(NAMESPACE) --wait
	@echo "✓ Uninstalled (PVCs preserved)"

.PHONY: destroy-cluster
destroy-cluster: ## Delete Kind cluster (local only)
ifeq ($(ENV),local)
	@kind delete cluster --name federator-suite-kind-cluster
	@echo "✓ Cluster destroyed"
else
	@echo "ERROR: destroy-cluster only works with ENV=local" && exit 1
endif

.PHONY: clean
clean: ## Clean generated files (Chart.lock, certs)
	@rm -rf Chart.lock certs/
	@echo "✓ Cleaned"

.PHONY: clean-all
clean-all: uninstall destroy-cluster clean ## Full cleanup (uninstall + destroy cluster + clean)
