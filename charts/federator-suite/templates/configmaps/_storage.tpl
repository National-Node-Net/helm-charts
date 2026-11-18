
{{- define "storage" -}}
{{/*
Storage handling for different cloud providers and local storage.

storage:
  provider: LOCAL  # LOCAL, S3, AZURE, or GCS
  aws:
    bucket: company-documents
    region: eu-west-2
    authentication:
      # podIdentity: Uses the Kubernetes ServiceAccount name and namespace.
      #              Requires an EKS Pod Identity Association mapping the
      #              ServiceAccount to an AWS IAM role (configured in AWS).
      #
      # irsa:        Uses the Kubernetes ServiceAccount annotation:
      #              eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/s3-storage-role
      #
      # secret:      Uses AWS access credentials from an existing Kubernetes Secret.
      type: podIdentity

      # Required when type: secret
      # existingSecret: aws-storage-credentials
      # secretKeys:
      #   accessKeyId: awsSecretAccessKeyId
      #   secretAccessKey: awsSecretAccessKey
      #   sessionToken: awsSessionToken  # optional

  azure:
    accountName: companystorage # mandatory for workload identity and account identity
    container: documents # mandatory for Azure storage configuration
    endpoint: https://companystorage.blob.core.windows.net
    authentication:
      # workloadIdentity: Uses the Kubernetes ServiceAccount annotation:
      #                   azure.workload.identity/client-id: "11111111-2222-4333-8444-555555555555"
      #                   Requires Pod label azure.workload.identity/use: "true"
      #                   and an Azure federated identity credential.
      #
      # connectionString: Uses an Azure Storage connection string from
      #                   an existing Kubernetes Secret.
      #
      # accountKey:       Uses an Azure Storage account key from
      #                   an existing Kubernetes Secret.
      type: workloadIdentity

      # Required when type: connectionString or accountKey
      # existingSecret: azure-storage-credentials
      # secretKeys:
      #   connectionString: myConnectionString  # connectionString only
      #   accountKey: myAccountKey              # accountKey only

  gcp:
    projectId: company-production
    bucket: company-documents
    authentication:
      # workloadIdentity: Uses GKE Workload Identity Federation.
      #                   Can use direct IAM principal bindings with the
      #                   Kubernetes ServiceAccount name and namespace.
      #                   Alternatively, for GCP service account impersonation,
      #                   uses the Kubernetes ServiceAccount annotation:
      #                   iam.gke.io/gcp-service-account: storage-app@company-production.iam.gserviceaccount.com
      #                   Requires corresponding GCP IAM bindings.
      #
      # serviceAccount:   Uses a Google service account JSON credentials file
      #                   from an existing Kubernetes Secret.
      #                   Mounted as a file and referenced through
      #                   GOOGLE_APPLICATION_CREDENTIALS.
      type: workloadIdentity

      # Required when type: serviceAccount
      # existingSecret: gcp-storage-credentials
      # secretKeys:
      #   credentialsJson: credentials.json

*/}}


{{- $storage := .Values.federatorClient.config.storage -}}
{{- $provider := required "storage.provider is required" $storage.provider | upper -}}

client.files.storage.provider={{ $provider }}

{{- if eq $provider "S3" }}
# AWS S3 Configuration
{{- $aws := $storage.aws | default dict }}
{{- $auth := dig "authentication" "type" "" $aws }}

{{- if not (has $auth (list "podIdentity" "irsa" "secret")) }}
{{- fail (printf "Unsupported AWS authentication type: %s (expected podIdentity, irsa or secret)" $auth) }}
{{- end }}

files.s3.bucket={{ required "storage.aws.bucket is required" ($aws.bucket | default "") }}
aws.s3.region={{ required "storage.aws.region is required" ($aws.region | default "") }}
aws.s3.access.key.id=${AWS_ACCESS_KEY_ID}
aws.s3.secret.access.key=${AWS_SECRET_ACCESS_KEY}

{{- if eq $auth "secret" }}
{{- $secret := dig "authentication" "existingSecret" "" $aws }}
{{- $accessKey := dig "authentication" "secretKeys" "accessKeyId" "" $aws }}
{{- $secretKey := dig "authentication" "secretKeys" "secretAccessKey" "" $aws }}
{{- $_ := required "storage.aws.authentication.existingSecret is required" $secret }}
{{- $_ := required "storage.aws.authentication.secretKeys.accessKeyId is required" $accessKey }}
{{- $_ := required "storage.aws.authentication.secretKeys.secretAccessKey is required" $secretKey }}
{{- end }}

{{- else if eq $provider "AZURE" }}
# Azure Storage Configuration
{{- $azure := $storage.azure | default dict }}
{{- $auth := dig "authentication" "type" "" $azure }}

{{- if not (has $auth (list "workloadIdentity" "connectionString" "accountKey")) }}
{{- fail (printf "Unsupported Azure authentication type: %s (expected workloadIdentity, connectionString or accountKey)" $auth) }}
{{- end }}

files.azure.container={{ required "storage.azure.container is required" ($azure.container | default "") }}

{{- if eq $auth "workloadIdentity" }}
azure.storage.account.name={{ required "storage.azure.accountName is required" ($azure.accountName | default "") }}

{{- else if eq $auth "accountKey" }}
azure.storage.account.name={{ required "storage.azure.accountName is required" ($azure.accountName | default "") }}
azure.storage.account.key=${AZURE_STORAGE_ACCOUNT_KEY}

{{- else if eq $auth "connectionString" }}
azure.storage.connection.string=${AZURE_STORAGE_CONNECTION_STRING}
{{- end }}

{{- with $azure.endpoint }}
azure.storage.endpoint={{ . }}
{{- end }}

{{- if or (eq $auth "connectionString") (eq $auth "accountKey") }}
{{- $secret := dig "authentication" "existingSecret" "" $azure }}
{{- $_ := required "storage.azure.authentication.existingSecret is required" $secret }}

{{- if eq $auth "connectionString" }}
{{- $_ := required "storage.azure.authentication.secretKeys.connectionString is required" (dig "authentication" "secretKeys" "connectionString" "" $azure) }}
{{- else }}
{{- $_ := required "storage.azure.authentication.secretKeys.accountKey is required" (dig "authentication" "secretKeys" "accountKey" "" $azure) }}
{{- end }}
{{- end }}

{{- else if eq $provider "GCP" }}
# GCP Storage Configuration
{{- $gcp := $storage.gcp | default dict }}
{{- $auth := dig "authentication" "type" "" $gcp }}

{{- if not (has $auth (list "workloadIdentity" "serviceAccount")) }}
{{- fail (printf "Unsupported GCP authentication type: %s (expected workloadIdentity or serviceAccount)" $auth) }}
{{- end }}

files.gcp.bucket={{ required "storage.gcp.bucket is required" ($gcp.bucket | default "") }}

{{- if eq $auth "serviceAccount" }}
{{- $_ := required "storage.gcp.authentication.existingSecret is required" (dig "authentication" "existingSecret" "" $gcp) }}
{{- $_ := required "storage.gcp.authentication.secretKeys.credentialsJson is required" (dig "authentication" "secretKeys" "credentialsJson" "" $gcp) }}
{{- end }}

{{- else if eq $provider "LOCAL" }}
# Local Storage Configuration
client.files.temp.dir={{ dig "local" "tempDir" "" $storage }}

{{- else }}
{{- fail (printf "Unsupported storage provider: %s (expected S3, AZURE, GCP or LOCAL)" $provider) }}
{{- end }}
{{- end -}}
