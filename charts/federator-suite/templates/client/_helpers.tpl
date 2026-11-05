{{- define "client.name" -}}
{{ default (printf "%s-federator-client" .Release.Name) .Values.federatorClient.deploymentName }}
{{- end -}}

{{- define "client.serviceAccountName" -}}
{{ default (printf "%s-federator-client" .Release.Name) .Values.federatorClient.serviceAccount.name }}
{{- end -}}