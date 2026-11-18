
{{/*
storage authentication - environment variables
supports AWS, Azure and GCP.
cloud identity modes require no static credentials.
*/}}
{{- define "storage,auth" -}}
{{- $storage := .Values.federatorClient.config.storage -}}
{{- $provider := upper (required "storage.provider is required" $storage.provider) -}}

{{- if eq $provider "S3" }}
  {{- $auth := $storage.aws.authentication }}
  {{- if eq $auth.type "secret" }}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ required "AWS existingSecret is required" $auth.existingSecret | quote }}
      key: {{ required "AWS accessKeyId is required" $auth.secretKeys.accessKeyId | quote }}
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $auth.existingSecret | quote }}
      key: {{ required "AWS secretAccessKey is required" $auth.secretKeys.secretAccessKey | quote }}
  {{- end }}

{{- else if eq $provider "AZURE" }}
  {{- $auth := $storage.azure.authentication }}
  {{- if eq $auth.type "connectionString" }}
- name: AZURE_STORAGE_CONNECTION_STRING
  valueFrom:
    secretKeyRef:
      name: {{ required "Azure existingSecret is required" $auth.existingSecret | quote }}
      key: {{ required "Azure connectionString key is required" $auth.secretKeys.connectionString | quote }}

  {{- else if eq $auth.type "accountKey" }}
- name: AZURE_STORAGE_ACCOUNT_KEY
  valueFrom:
    secretKeyRef:
      name: {{ required "Azure existingSecret is required" $auth.existingSecret | quote }}
      key: {{ required "Azure accountKey is required" $auth.secretKeys.accountKey | quote }}
  {{- end }}

{{- else if eq $provider "GCP" }}
  {{- $auth := $storage.gcp.authentication }}
  {{- if eq $auth.type "serviceAccount" }}
- name: GOOGLE_APPLICATION_CREDENTIALS 
  value: /etc/gcp/credentials.json
  {{- end }}
{{- end }}
{{- end -}}


{{/*
Storage authentication - volume mounts
Only needed for GCP service account JSON.
*/}}
{{- define "storage.auth.volumeMounts" -}}
{{- $storage := .Values.federatorClient.config.storage -}}
{{- if eq (upper $storage.provider) "GCP" }}
  {{- if eq $storage.gcp.authentication.type "serviceAccount" }}
- name: gcp-storage-credentials
  mountPath: /etc/gcp
  readOnly: true
  {{- end }}
{{- end }}
{{- end -}}


{{/*storage authentication - volumes
only needed for GCP service account JSON.
*/}}
{{- define "storage.auth.volumes" -}}
{{- $storage := .Values.federatorClient.config.storage -}}
{{- if eq (upper $storage.provider) "GCP" }}
  {{- $auth := $storage.gcp.authentication }}
  {{- if eq $auth.type "serviceAccount" }}
- name: gcp-storage-credentials
  secret:
    secretName: {{ required "GCP existingSecret is required" $auth.existingSecret | quote }}
    items:
      - key: {{ required "GCP credentialsJson key is required" $auth.secretKeys.credentialsJson | quote }}
        path: credentials.json
  {{- end }}
{{- end }}
{{- end -}}
