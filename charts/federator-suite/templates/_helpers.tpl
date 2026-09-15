{{/*
Expand the name of the chart.
*/}}
{{- define "federator-suite.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Determine if Kafka subchart should be enabled (inverse of external flag)
*/}}
{{- define "federator-suite.kafka.enabled" -}}
{{- not .Values.kafka.external }}
{{- end }}

{{/*
Determine if Valkey subchart should be enabled (inverse of external flag)
*/}}
{{- define "federator-suite.valkey.enabled" -}}
{{- not .Values.valkey.external }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "federator-suite.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "federator-suite.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "federator-suite.labels" -}}
helm.sh/chart: {{ include "federator-suite.chart" . }}
{{ include "federator-suite.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "federator-suite.selectorLabels" -}}
app.kubernetes.io/name: {{ include "federator-suite.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Federator Server labels
*/}}
{{- define "federator-suite.server.labels" -}}
helm.sh/chart: {{ include "federator-suite.chart" . }}
app: federator-server
{{ include "federator-suite.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: server
{{- end }}

{{/*
Federator Client labels
*/}}
{{- define "federator-suite.client.labels" -}}
helm.sh/chart: {{ include "federator-suite.chart" . }}
app: federator-client
{{ include "federator-suite.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: client
{{- end }}

{{/*
Service account name for server
*/}}
{{- define "federator-suite.server.serviceAccountName" -}}
{{- if .Values.federatorServer.serviceAccount.create }}
{{- default (printf "%s-federator-server" .Release.Name) .Values.federatorServer.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.federatorServer.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Service account name for client
*/}}
{{- define "federator-suite.client.serviceAccountName" -}}
{{- if .Values.federatorClient.serviceAccount.create }}
{{- default (printf "%s-federator-client" .Release.Name) .Values.federatorClient.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.federatorClient.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Server full name (with release prefix for multi-org)
*/}}
{{- define "federator-suite.server.fullname" -}}
{{- printf "%s-federator-server" .Release.Name }}
{{- end }}

{{/*
Client full name (with release prefix for multi-org)
*/}}
{{- define "federator-suite.client.fullname" -}}
{{- printf "%s-federator-client" .Release.Name }}
{{- end }}

{{/*
Generic resource name helper (with release prefix)
*/}}
{{- define "federator-suite.resourceName" -}}
{{- $name := . }}
{{- printf "%s-%s" $.Release.Name $name }}
{{- end }}

{{/*
Kafka bootstrap servers
Returns the appropriate Kafka bootstrap servers based on external flag
Strimzi creates service: <cluster-name>-kafka-bootstrap
*/}}
{{- define "federator-suite.kafka.bootstrapServers" -}}
{{- if .Values.kafka.external }}
{{- .Values.kafka.externalConfig.bootstrapServers }}
{{- else }}
{{- printf "%s-kafka:9092" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Kafka security protocol
*/}}
{{- define "federator-suite.kafka.securityProtocol" -}}
{{- if .Values.kafka.external }}
{{- .Values.kafka.externalConfig.securityProtocol }}
{{- else }}
{{- if .Values.kafka.listeners }}
{{- .Values.kafka.listeners.client.protocol | default "SASL_PLAINTEXT" }}
{{- else }}
SASL_PLAINTEXT
{{- end }}
{{- end }}
{{- end }}

{{/*
Kafka SASL mechanism
*/}}
{{- define "federator-suite.kafka.saslMechanism" -}}
{{- if .Values.kafka.external -}}
{{- .Values.kafka.externalConfig.saslMechanism -}}
{{- else -}}
SCRAM-SHA-512
{{- end -}}
{{- end -}}

{{/*
Valkey host
*/}}
{{- define "federator-suite.valkey.host" -}}
{{- if .Values.valkey.external }}
{{- .Values.valkey.externalConfig.host }}
{{- else }}
{{- printf "%s-valkey-primary" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Valkey port
*/}}
{{- define "federator-suite.valkey.port" -}}
{{- if .Values.valkey.external }}
{{- .Values.valkey.externalConfig.port | default 6379 }}
{{- else }}
{{- .Values.valkey.valkey.primary.service.port | default 6379 }}
{{- end }}
{{- end }}

{{/*
Valkey password (from secret or plain value)
*/}}
{{- define "federator-suite.valkey.password" -}}
{{- if .Values.valkey.external }}
{{- if .Values.valkey.externalConfig.auth.enabled }}
{{- .Values.secrets.valkeyAuth.token | default .Values.valkey.externalConfig.auth.token }}
{{- else }}
{{- "" }}
{{- end }}
{{- else }}
{{- if .Values.valkey.valkey.auth.enabled }}
{{- .Values.valkey.valkey.auth.password }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Get Valkey/Redis username
*/}}
{{- define "federator-suite.valkey.username" -}}
{{- if .Values.valkey.external }}
{{- if .Values.valkey.externalConfig.auth.enabled }}
{{- .Values.valkey.externalConfig.auth.username | default "default" }}
{{- else }}
{{- "" }}
{{- end }}
{{- else }}
{{- if .Values.valkey.valkey.auth.enabled }}
{{- .Values.valkey.valkey.auth.username | default "" }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate configuration - basic checks
*/}}
{{- define "federator-suite.validateConfig" -}}
{{- if and .Values.kafka.external (not .Values.kafka.externalConfig.bootstrapServers) }}
{{- fail "ERROR: kafka.external is true but kafka.externalConfig.bootstrapServers is not set" }}
{{- end }}
{{- if and .Values.valkey.external (not .Values.valkey.externalConfig.host) }}
{{- fail "ERROR: valkey.external is true but valkey.externalConfig.host is not set" }}
{{- end }}
{{- /* Vault validation (always enabled) — cloud provider derived from global.clusterType */ -}}
{{- if not .Values.vault.devMode }}
{{- $cp := include "federator-suite.cloudProvider" . }}
{{- if not (or (eq $cp "aws") (eq $cp "azure") (eq $cp "gcp")) }}
{{- fail (printf "ERROR: cloud provider must be aws, azure, or gcp — got: %s (from global.clusterType or vault.cloudProvider)" $cp) }}
{{- end }}
{{- if and .Values.vault.setup.enabled (eq .Values.vault.secretsManager.secretName "PLACEHOLDER_SECRETS_MANAGER_NAME") }}
{{- fail "ERROR: vault.secretsManager.secretName is still a placeholder — set from Terraform output" }}
{{- end }}
{{- if eq $cp "aws" }}
{{- if eq (.Values.vault.seal.aws.kmsKeyId | default "PLACEHOLDER_KMS_KEY_ID") "PLACEHOLDER_KMS_KEY_ID" }}
{{- fail "ERROR: vault.seal.aws.kmsKeyId is still a placeholder — set from Terraform output" }}
{{- end }}
{{- else if eq $cp "azure" }}
{{- if eq (.Values.vault.seal.azure.tenantId | default "PLACEHOLDER_TENANT_ID") "PLACEHOLDER_TENANT_ID" }}
{{- fail "ERROR: vault.seal.azure.tenantId is still a placeholder — set from Terraform output" }}
{{- end }}
{{- else if eq $cp "gcp" }}
{{- if eq (.Values.vault.seal.gcp.project | default "PLACEHOLDER_PROJECT") "PLACEHOLDER_PROJECT" }}
{{- fail "ERROR: vault.seal.gcp.project is still a placeholder — set from Terraform output" }}
{{- end }}
{{- end }}
{{- end }}{{/* end vault devMode skip */}}
{{- /* Certificate Manager validation (only when enabled) */ -}}
{{- if .Values.certificateManager.enabled }}
{{- if eq .Values.certificateManager.image.tag "PLACEHOLDER_IMAGE_TAG" }}
{{- fail "ERROR: certificateManager.image.tag is still a placeholder — set to the latest image tag" }}
{{- end }}
{{- end }}
{{- /* Certificate validation disabled for templating - secrets should be provided at deployment time */ -}}
{{- /* Single-switch Istio model: serviceMesh.istio.enabled controls all Istio resources */ -}}
{{- end }}

{{/*
Image pull policy helper
*/}}
{{- define "federator-suite.imagePullPolicy" -}}
{{- if eq .Values.global.environment "local" }}
{{- "Never" }}
{{- else }}
{{- "IfNotPresent" }}
{{- end }}
{{- end }}

{{/*
Istio sidecar annotation
*/}}
{{- define "federator-suite.istio.inject" -}}
{{- if .Values.serviceMesh.istio.enabled }}
sidecar.istio.io/inject: "true"
{{- else }}
sidecar.istio.io/inject: "false"
{{- end }}
{{- end }}

{{/*
Generate org prefix for topic names
*/}}
{{- define "federator-suite.orgPrefix" -}}
{{- if .Values.global.orgPrefix }}
{{- .Values.global.orgPrefix }}
{{- else }}
{{- .Values.global.orgName | lower }}
{{- end }}
{{- end }}

{{/*
Kafka topic prefix (for Deprecated topics)
*/}}
{{- define "federator-suite.kafkaTopicPrefix" -}}
{{- if .Values.federatorServer.config.kafkaTopicPrefix }}
{{- .Values.federatorServer.config.kafkaTopicPrefix }}
{{- else }}
{{- printf "Deprecated%s" (.Values.global.orgName | upper) }}
{{- end }}
{{- end }}

{{/*
Client properties file content

Why this helper exists:
- Keeps large application properties in one place
- Ensures both local and cloud deployments derive values consistently
- Centralizes Kafka/Valkey/security substitutions from Helm values
*/}}
{{- define "federator-suite.clientProperties" -}}
# Kafka Configuration (Sender)
kafka.sender.defaultKeySerializerClass=org.apache.kafka.common.serialization.BytesSerializer
kafka.sender.defaultValueSerializerClass=org.apache.kafka.common.serialization.BytesSerializer

# Kafka Bootstrap Servers
kafka.bootstrapServers={{ include "federator-suite.kafka.bootstrapServers" . }}
{{- if or .Values.kafka.external (and (not .Values.kafka.external) .Values.kafka.sasl) }}
kafka.additional.security.protocol={{ include "federator-suite.kafka.securityProtocol" . }}
kafka.additional.sasl.mechanism={{ include "federator-suite.kafka.saslMechanism" . }}
kafka.additional.sasl.jaas.config={{ .Values.secrets.kafkaAuth.jaasConfig }}
{{- end }}

# Topic Configuration
kafka.topic.prefix={{ include "federator-suite.kafkaTopicPrefix" . }}
kafka.consumerGroup={{ .Values.federatorClient.config.consumerGroup | default (printf "ndtp.dbt.gov.uk.%s" (.Values.global.orgName | lower)) }}

# Redis/Valkey Configuration
{{- $password := include "federator-suite.valkey.password" . -}}
{{- $username := include "federator-suite.valkey.username" . -}}
{{- $redisTlsEnabled := false -}}
{{- if .Values.valkey.external }}
{{- if kindIs "bool" .Values.valkey.external }}
{{- $redisTlsEnabled = true }}
{{- else if .Values.valkey.external.enabled }}
{{- $redisTlsEnabled = true }}
{{- end }}
{{- else if and .Values.valkey.enabled .Values.valkey.valkey.primary.tls }}
{{- $redisTlsEnabled = .Values.valkey.valkey.primary.tls.enabled }}
{{- end }}
redis.host={{ include "federator-suite.valkey.host" . }}
redis.port={{ include "federator-suite.valkey.port" . }}
redis.tls.enabled={{ ternary "true" "false" $redisTlsEnabled }}
redis.prefix={{ .Values.federatorClient.config.redisPrefix | default (printf "federator-client-%s" (.Values.global.orgName | lower)) }}
{{- if $password }}
redis.username={{ $username }}
redis.password={{ $password }}
redis.aes.key=
{{- else }}
redis.username=
redis.password=
redis.aes.key=
{{- end }}

# Common Configuration
common.configuration=/common-configuration/common-configuration.properties

# JobRunr Configuration
org.jobrunr.jobs.default-allow-concurrent-execution=false
jobs.dashboard.port=8085
jobs.dashboard.enabled=true

# Management Node
management.node.cache.ttl.seconds=60
management.node.request.timeout=60
management.node.base.url={{ .Values.global.managementNode.baseUrl }}

# Client TLS Configuration
client.mtlsEnabled={{ .Values.federatorClient.config.mtlsEnabled | default true }}
client.tlsEnabled={{ .Values.federatorClient.config.tlsEnabled | default true }}
client.p12FilePath=/secrets/federation-client-p12/{{ .Values.secrets.certificates.external.clientP12Filename }}
client.p12Password={{ .Values.secrets.certificates.external.clientP12Password }}
client.truststoreFilePath=/secrets/federation-cert/keycloak.truststore.jks
client.truststorePassword={{ .Values.secrets.certificates.external.truststorePassword }}
client.keystorePassword={{ .Values.secrets.certificates.external.clientKeystorePassword }}

# Connection Configuration
connections.configuration=/client-connections/connection-configuration.json

# File Storage Configuration
client.files.storage.provider={{ .Values.federatorClient.config.storage.provider | upper }}
{{- if eq (.Values.federatorClient.config.storage.provider | upper) "S3" }}
files.s3.bucket={{ .Values.federatorClient.config.storage.s3.bucket }}
aws.s3.region={{ .Values.federatorClient.config.storage.s3.region }}
{{- else if eq (.Values.federatorClient.config.storage.provider | upper) "AZURE" }}
azure.storage.connection.string={{ .Values.federatorClient.config.storage.azure.connectionString }}
azure.storage.account.name={{ .Values.federatorClient.config.storage.azure.accountName }}
azure.storage.endpoint={{ .Values.federatorClient.config.storage.azure.endpoint }}
files.azure.container={{ .Values.federatorClient.config.storage.azure.container }}
{{- else if eq (.Values.federatorClient.config.storage.provider | upper) "GCP" }}
files.gcp.bucket={{ .Values.federatorClient.config.storage.gcp.bucket }}
{{- else if eq (.Values.federatorClient.config.storage.provider | upper) "LOCAL" }}
client.files.temp.dir={{ .Values.federatorClient.config.storage.local.tempDir | default "" }}
{{- end }}
{{- end }}

{{/*
Server properties file content

Why this helper exists:
- Uses the same value sources as the client helper
- Avoids duplicated templating logic across ConfigMaps
- Keeps storage/Kafka/Valkey/auth wiring consistent per environment
*/}}
{{- define "federator-suite.serverProperties" -}}
# Kafka Configuration (Consumer)
kafka.defaultKeyDeserializerClass=org.apache.kafka.common.serialization.StringDeserializer
kafka.defaultValueDeserializerClass=uk.gov.dbt.ndtp.federator.access.AccessMessageDeserializer
kafka.consumerGroup=server.consumer
kafka.pollDuration=PT10S
kafka.pollRecords=100

# Shared Headers
shared.headers=Security-Label^Content-Type
filter.shareAll=false

# Client Name
client.name={{ .Values.federatorServer.config.clientName | default (printf "ndtp.dbt.gov.uk.%s" (.Values.global.orgName | lower)) }}

# Server Configuration
server.port={{ .Values.federatorServer.config.serverPort }}
server.keepAliveTime={{ .Values.federatorServer.config.keepAliveTime | default 10 }}

# Kafka Bootstrap Servers
kafka.bootstrapServers={{ include "federator-suite.kafka.bootstrapServers" . }}
{{- if or .Values.kafka.external (and (not .Values.kafka.external) .Values.kafka.sasl) }}
kafka.additional.security.protocol={{ include "federator-suite.kafka.securityProtocol" . }}
kafka.additional.sasl.mechanism={{ include "federator-suite.kafka.saslMechanism" . }}
kafka.additional.sasl.jaas.config={{ .Values.secrets.kafkaAuth.jaasConfig }}
{{- end }}

# Server mTLS Configuration
server.mtlsEnabled={{ .Values.federatorServer.config.mtlsEnabled | default true }}
server.truststoreFilePath=/secrets/federation-cert/keycloak.truststore.jks
server.truststorePassword={{ .Values.secrets.certificates.external.truststorePassword }}
server.p12FilePath=/secrets/federation-server-p12/{{ .Values.secrets.certificates.external.serverP12Filename }}
server.p12Password={{ .Values.secrets.certificates.external.serverP12Password }}
server.keystorePassword={{ .Values.secrets.certificates.external.serverKeystorePassword }}

# Common Configuration
common.configuration=/common-configuration/common-configuration.properties

# JobRunr Configuration
org.jobrunr.jobs.default-allow-concurrent-execution=false
jobs.dashboard.port=8085
jobs.dashboard.enabled=true

# Management Node
management.node.cache.ttl.seconds=60
management.node.request.timeout=60
management.node.base.url={{ .Values.global.managementNode.baseUrl }}

# Redis/Valkey Configuration
{{- $password := include "federator-suite.valkey.password" . -}}
{{- $username := include "federator-suite.valkey.username" . -}}
{{- $redisTlsEnabled := false -}}
{{- if .Values.valkey.external }}
{{- if kindIs "bool" .Values.valkey.external }}
{{- $redisTlsEnabled = true }}
{{- else if .Values.valkey.external.enabled }}
{{- $redisTlsEnabled = true }}
{{- end }}
{{- else if and .Values.valkey.enabled .Values.valkey.valkey.primary.tls }}
{{- $redisTlsEnabled = .Values.valkey.valkey.primary.tls.enabled }}
{{- end }}
redis.host={{ include "federator-suite.valkey.host" . }}
redis.port={{ include "federator-suite.valkey.port" . }}
redis.tls.enabled={{ ternary "true" "false" $redisTlsEnabled }}
redis.prefix={{ .Values.federatorServer.config.redisPrefix | default (printf "federator-server-%s" (.Values.global.orgName | lower)) }}
{{- if $password }}
redis.username={{ $username }}
redis.password={{ $password }}
{{- else }}
redis.username=
redis.password=
{{- end }}

# File Storage Configuration
file.stream.chunk.size=1000
{{- if eq (.Values.federatorServer.config.storage.provider | upper) "S3" }}
files.storage.provider=S3
files.s3.bucket={{ .Values.federatorServer.config.storage.s3.bucket }}
aws.s3.region={{ .Values.federatorServer.config.storage.s3.region }}
{{- else if eq (.Values.federatorServer.config.storage.provider | upper) "AZURE" }}
files.storage.provider=AZURE
azure.storage.connection.string={{ .Values.federatorServer.config.storage.azure.connectionString }}
azure.storage.account.name={{ .Values.federatorServer.config.storage.azure.accountName }}
azure.storage.endpoint={{ .Values.federatorServer.config.storage.azure.endpoint }}
files.azure.container={{ .Values.federatorServer.config.storage.azure.container }}
{{- else if eq (.Values.federatorServer.config.storage.provider | upper) "GCP" }}
files.storage.provider=GCP
files.gcp.bucket={{ .Values.federatorServer.config.storage.gcp.bucket }}
{{- end }}
{{- end }}

{{/* ======================================================================
     Vault Helpers
     ====================================================================== */}}

{{/*
Cloud provider — derived from global.clusterType or explicit vault.cloudProvider.
Mapping: eks → aws, aks → azure, gke → gcp.
Explicit vault.cloudProvider always wins if set.
Returns empty string when vault.devMode is true (local/KIND deployment).
*/}}
{{- define "federator-suite.cloudProvider" -}}
{{- if .Values.vault.devMode -}}
{{- /* devMode: no cloud provider needed */ -}}
{{- else if .Values.vault.cloudProvider }}
{{- .Values.vault.cloudProvider }}
{{- else }}
{{- $ct := .Values.global.clusterType | default "" }}
{{- if eq $ct "eks" }}aws
{{- else if eq $ct "aks" }}azure
{{- else if eq $ct "gke" }}gcp
{{- else }}
{{- fail (printf "ERROR: Cannot determine cloud provider from global.clusterType '%s' — expected: eks, aks, or gke. Set vault.cloudProvider explicitly or enable vault.devMode for local deployment." $ct) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Vault internal address
Returns the HTTP address of the Vault leader within the cluster.
*/}}
{{- define "federator-suite.vault.addr" -}}
{{- $replicas := .Values.vault.ha.replicas | default 1 | int }}
{{- if gt $replicas 1 }}
{{- printf "http://%s-vault-active.%s.svc.cluster.local:8200" .Release.Name .Release.Namespace }}
{{- else }}
{{- printf "http://%s-vault.%s.svc.cluster.local:8200" .Release.Name .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Vault any-pod address (plain ClusterIP — routes to all pods, works before init)
Use this for pre-initialisation operations where vault-active has no endpoints.
*/}}
{{- define "federator-suite.vault.any.addr" -}}
{{- printf "http://%s-vault.%s.svc.cluster.local:8200" .Release.Name .Release.Namespace }}
{{- end }}

{{/*
Vault service account name
*/}}
{{- define "federator-suite.vault.serviceAccountName" -}}
{{- if .Values.vault.serviceAccount.name }}
{{- .Values.vault.serviceAccount.name }}
{{- else }}
{{- printf "%s-vault-sa" .Release.Name }}
{{- end }}
{{- end }}

{{/* ======================================================================
     Certificate Manager Helpers
     ====================================================================== */}}

{{/*
Certificate manager full name
*/}}
{{- define "federator-suite.certificateManager.fullname" -}}
{{- printf "%s-certificate-manager" .Release.Name }}
{{- end }}

{{/*
Certificate manager service account name
*/}}
{{- define "federator-suite.certificateManager.serviceAccountName" -}}
{{- if .Values.certificateManager.serviceAccount.name }}
{{- .Values.certificateManager.serviceAccount.name }}
{{- else }}
{{- printf "%s-certificate-manager" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Shared cert storage PVC claim name
Used by certificate-manager (read-write) and server/client deployments (read-only)
*/}}
{{- define "federator-suite.certStorage.claimName" -}}
{{- printf "%s-cert-storage" .Release.Name }}
{{- end }}

{{/* ======================================================================
     OPA (Open Policy Agent) Helpers
     ====================================================================== */}}

{{/*
OPA full name
*/}}
{{- define "federator-suite.opa.fullname" -}}
{{- printf "%s-opa" .Release.Name }}
{{- end }}

{{/*
OPA service account name
*/}}
{{- define "federator-suite.opa.serviceAccountName" -}}
{{- if .Values.opa.serviceAccount.create }}
{{- default (printf "%s-opa" .Release.Name) .Values.opa.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.opa.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
OPA internal address — ClusterIP Service DNS for a future PEP to call.
*/}}
{{- define "federator-suite.opa.addr" -}}
{{- printf "http://%s-opa.%s.svc.cluster.local:%v" .Release.Name .Release.Namespace (.Values.opa.service.port | default 8181) }}
{{- end }}
