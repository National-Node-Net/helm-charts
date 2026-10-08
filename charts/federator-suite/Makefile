# Federator Suite Helm Chart Makefile

.PHONY: help
help: ## Show this help message
	@echo "Federator Suite Deployment"
	@echo "========================="
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  ENV          Environment (local|dev|prod)  default: local"
	@echo "  ORG          Organization (bcc|env|heg|hmrc)    default: bcc"
	@echo "  RELEASE_NAME Release name                  default: federator-suite"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy-local ORG=bcc           # Deploy BCC locally (Kind)"
	@echo "  make deploy ENV=dev ORG=bcc         # Deploy BCC to AWS EKS dev"
	@echo "  make upgrade ENV=dev ORG=bcc        # Fast upgrade (no checks)"

# ============================================
# Configuration
# ============================================

ENV ?= local
RELEASE_NAME ?= federator-suite
ORG ?= bcc
CHART_PATH = .

COMPONENT_VALUES = -f values/common-values.yaml -f values/kafka.yaml -f values/valkey.yaml -f values/vault.yaml -f values/certificate-manager.yaml -f values/opa.yaml -f values/federator.yaml -f values/kafka-ui.yaml -f values/valkey-ui.yaml -f values/istio.yaml

ifeq ($(ENV),local)
VALUES_FILES = $(COMPONENT_VALUES) -f values/overrides/local/local.yaml -f values/overrides/local/$(ORG).yaml
SECRETS_FILE = values/overrides/local/secrets.yaml
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
	@$(MAKE) _setup-cluster
	@$(MAKE) _build-deps
	@$(MAKE) _istio-inject-if-enabled
	@echo "==> Installing chart..."
ifeq ($(ENV),local)
	@helm upgrade --install $(RELEASE_NAME) $(CHART_PATH) \
	-n $(NAMESPACE) \
$(VALUES_FILES) \
	--wait --timeout 10m
else
	@helm upgrade --install $(RELEASE_NAME) $(CHART_PATH) \
	-n $(NAMESPACE) \
$(VALUES_FILES) \
	--wait --timeout 10m
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
	@helm upgrade $(RELEASE_NAME) $(CHART_PATH) \
	-n $(NAMESPACE) \
$(VALUES_FILES)
	@echo "==> ✓ Upgrade complete!"

# ============================================
# Internal Targets
# ============================================

.PHONY: _setup-cluster
_setup-cluster:
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

.PHONY: _build-deps
_build-deps:
	@echo "==> Building dependencies..."
	@if ! helm repo list 2>/dev/null | grep -q '^bitnami[[:space:]]'; then \
helm repo add bitnami https://charts.bitnami.com/bitnami; \
fi
	@if ! helm repo list 2>/dev/null | grep -q '^hashicorp[[:space:]]'; then \
		helm repo add hashicorp https://helm.releases.hashicorp.com; \
	fi
	@helm repo update 2>/dev/null || echo "  ⚠ Repo update failed (offline/firewall) - using cached charts"
	@cd charts/valkey && helm dependency build --skip-refresh 2>/dev/null || true
	@cd charts/vault && helm dependency build --skip-refresh 2>/dev/null || true

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
	@test -f $(SECRETS_FILE) || (echo "ERROR: $(SECRETS_FILE) not found" && exit 1)
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
		echo "  ⚠ No cluster found — will be created by _setup-cluster"; \
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
	@echo "==> Checking: $(SECRETS_FILE)"
	@test -f $(SECRETS_FILE) || (echo "ERROR: Secrets file not found" && exit 1)
	@grep -q "truststoreJks:" $(SECRETS_FILE) || echo "  ⚠ truststoreJks not found"
	@grep -q "serverKeystoreJks:" $(SECRETS_FILE) || echo "  ⚠ serverKeystoreJks not found"
	@grep -q "clientKeystoreJks:" $(SECRETS_FILE) || echo "  ⚠ clientKeystoreJks not found"
	@echo "  ✓ Secrets check complete"

.PHONY: pre-deploy-check
pre-deploy-check: validate check-cluster check-secrets ## Run all pre-deployment checks
	@echo "==> ✓ Pre-deploy checks passed"

.PHONY: test
test: test-render lint ## Run all tests

.PHONY: test-render
test-render: ## Test template rendering
	@echo "==> Rendering templates..."
	@helm template test-$(ORG) $(CHART_PATH) \
$(VALUES_FILES) \
	--namespace $(NAMESPACE) \
	--debug 2>&1 | head -50
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
	@echo "==> Health check: $(RELEASE_NAME) in $(NAMESPACE)"
	@echo ""
	@echo "All Pods:"
	@kubectl get pods -n $(NAMESPACE)
	@echo ""
	@FAILED=0; \
	NOT_RUNNING=$$(kubectl get pods -n $(NAMESPACE) --no-headers 2>/dev/null | grep -v 'Running\|Completed' || true); \
	if [ -n "$$NOT_RUNNING" ]; then \
		echo "⚠ Pods not in Running state:"; \
		echo "$$NOT_RUNNING"; \
		FAILED=1; \
	fi; \
	NOT_READY=$$(kubectl get pods -n $(NAMESPACE) --no-headers 2>/dev/null | awk '{split($$2,a,"/"); if(a[1]!=a[2] && $$3=="Running") print $$0}' || true); \
	if [ -n "$$NOT_READY" ]; then \
		echo "⚠ Pods running but not ready:"; \
		echo "$$NOT_READY"; \
		FAILED=1; \
	fi; \
	if [ $$FAILED -eq 0 ]; then \
		echo "✓ All pods Running and Ready"; \
	fi
	@echo ""
	@echo "Services:"
	@kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "Application health:"
	@SERVER_POD=$$(kubectl get pod -l app=federator-server -n $(NAMESPACE) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$SERVER_POD" ]; then echo "  ⚠ server pod not found"; else \
		kubectl exec -n $(NAMESPACE) $$SERVER_POD -c federator-server -- sh -c "ps aux | grep -q '[j]ava.*FederatorServer' && echo '  ✓ Server process running' || echo '  ⚠ Server process not found'" 2>/dev/null || echo "  ⚠ Cannot check server process"; \
	fi
	@CLIENT_POD=$$(kubectl get pod -l app=federator-client -n $(NAMESPACE) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$CLIENT_POD" ]; then echo "  ⚠ client pod not found"; else \
		kubectl exec -n $(NAMESPACE) $$CLIENT_POD -c federator-client -- sh -c "if command -v wget >/dev/null; then wget -qO- --timeout=2 http://localhost:8085/ 2>/dev/null | grep -q 'JobRunr' && echo '  ✓ JobRunr dashboard responding' || echo '  ⚠ JobRunr not responding'; else echo '  ⚠ wget not available'; fi" 2>/dev/null || echo "  ⚠ Cannot check JobRunr"; \
	fi
	@echo ""
	@echo "Vault health:"
	@VAULT_POD=$$(kubectl get pod -l app.kubernetes.io/name=vault,component=server -n $(NAMESPACE) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$VAULT_POD" ]; then echo "  ⚠ vault pod not found"; else \
		kubectl exec -n $(NAMESPACE) $$VAULT_POD -- vault status 2>/dev/null && echo "  ✓ Vault responding" || echo "  ⚠ Vault not responding (may need init)"; \
	fi
	@echo ""
	@echo "Certificate Manager health:"
	@CM_POD=$$(kubectl get pod -l app=certificate-manager -n $(NAMESPACE) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$CM_POD" ]; then echo "  ⚠ certificate-manager pod not found"; else \
		kubectl exec -n $(NAMESPACE) $$CM_POD -- sh -c "pgrep -f 'java.*certificate-manager' > /dev/null && echo '  ✓ Certificate manager process running' || echo '  ⚠ Certificate manager process not found'" 2>/dev/null || echo "  ⚠ Cannot check certificate manager"; \
	fi
	@echo ""
	@echo "OPA health:"
	@OPA_POD=$$(kubectl get pod -l app=opa -n $(NAMESPACE) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$OPA_POD" ]; then echo "  ⚠ opa pod not found"; else \
		READY=$$(kubectl get pod "$$OPA_POD" -n $(NAMESPACE) -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null); \
		if [ "$$READY" = "true" ]; then echo "  ✓ OPA responding (readiness probe: /health/ready)"; else echo "  ⚠ OPA not ready"; fi; \
	fi
	@echo ""
	@echo "Error check (all pods, last 100 lines):"
	@ERROR_FOUND=0; \
	for pod in $$(kubectl get pods -n $(NAMESPACE) -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do \
		ERRORS=$$(kubectl logs $$pod -n $(NAMESPACE) --tail=100 --all-containers 2>/dev/null | grep -Ei 'error|exception|fatal|crash' | grep -Eiv 'loglevel.*error|error.*level|expected.*error' || true); \
		if [ -n "$$ERRORS" ]; then \
			echo "⚠ Errors in $$pod:"; \
			echo "$$ERRORS" | head -5; \
			ERROR_FOUND=1; \
		fi; \
	done; \
	if [ $$ERROR_FOUND -eq 0 ]; then \
		echo "  ✓ No errors found in any pods"; \
	fi

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
	@echo "Starting port forwards..."
	@kubectl port-forward -n $(NAMESPACE) svc/kafka-ui 8088:8080 > /dev/null 2>&1 &
	@kubectl port-forward -n $(NAMESPACE) svc/valkey-ui 5540:5540 > /dev/null 2>&1 &
	@kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-federator-client 8085:8085 > /dev/null 2>&1 &
	@kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-vault-ui 8200:8200 > /dev/null 2>&1 &
	@kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-opa 8181:8181 > /dev/null 2>&1 &
	@sleep 2
	@echo "  ✓ JobRunr:    http://localhost:8085"
	@echo "  ✓ Kafka UI:   http://localhost:8088"
	@echo "  ✓ Valkey UI:  http://localhost:5540"
	@echo "  ✓ Vault UI:   http://localhost:8200"
	@echo "  ✓ OPA:        http://localhost:8181"
	@echo ""
	@echo "Stop: make stop-port-forwards"

.PHONY: stop-port-forwards
stop-port-forwards: ## Stop all port forwards
	@pids=$$(ps aux | grep '[k]ubectl port-forward' | awk '{print $$2}'); \
	if [ -n "$$pids" ]; then echo "$$pids" | xargs kill 2>/dev/null; echo "✓ Stopped"; \
	else echo "No port forwards running"; fi

.PHONY: port-forward-status
port-forward-status: ## Show active port forwards
	@if ps aux | grep -v grep | grep -q "kubectl port-forward"; then \
	echo "Active:"; \
	ps aux | grep -v grep | grep "kubectl port-forward" | while read -r line; do \
	svc=$$(echo "$$line" | grep -oP 'svc/[^ ]+'); \
	ports=$$(echo "$$line" | grep -oP '\d+:\d+' | head -1); \
	echo "  $$svc → $$ports"; \
	done; \
	else \
	echo "No port forwards running. Start: make port-forward-all"; \
	fi

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
ifeq ($(ENV),local)
	@set -e; \
	echo "==> Initializing Vault ($(RELEASE_NAME)-vault-0)..."; \
	VAULT_INIT=$$(kubectl exec -n $(NAMESPACE) $(RELEASE_NAME)-vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json); \
	UNSEAL_KEY=$$(echo "$$VAULT_INIT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['unseal_keys_b64'][0])"); \
	ROOT_TOKEN=$$(echo "$$VAULT_INIT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['root_token'])"); \
	echo "  Unsealing..."; \
	kubectl exec -n $(NAMESPACE) $(RELEASE_NAME)-vault-0 -- vault operator unseal "$$UNSEAL_KEY"; \
	echo "  Enabling KV mounts..."; \
	kubectl exec -n $(NAMESPACE) $(RELEASE_NAME)-vault-0 -- sh -c "VAULT_TOKEN=$$ROOT_TOKEN vault secrets enable -version=2 -path=secret kv 2>/dev/null || true"; \
	kubectl exec -n $(NAMESPACE) $(RELEASE_NAME)-vault-0 -- sh -c "VAULT_TOKEN=$$ROOT_TOKEN vault secrets enable -version=2 -path=node-net kv 2>/dev/null || true"; \
	echo "  Creating cert-manager vault-token secret..."; \
	kubectl create secret generic $(RELEASE_NAME)-certificate-manager-vault-token \
	  --from-literal=vault-token="$$ROOT_TOKEN" \
	  -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -; \
	echo "==> Vault initialized"; \
	echo "    Unseal key : $$UNSEAL_KEY"; \
	echo "    Root token : $$ROOT_TOKEN"; \
	echo "    WARNING: save these credentials safely!"
else
	@echo "ERROR: init-vault only works with ENV=local" && exit 1
endif

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
