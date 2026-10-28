{{- define "server.name" -}}
{{ default (printf "%s-federator-server" .Release.Name) .Values.federatorServer.deploymentName }}
{{- end -}}

{{- define "server.serviceAccountName" -}}
{{ default (printf "%s-federator-server" .Release.Name) .Values.federatorServer.serviceAccount.name }}
{{- end -}}