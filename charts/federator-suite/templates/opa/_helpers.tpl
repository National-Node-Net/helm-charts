{{- define "opa.name" -}}
{{- default (printf "%s-opa" .Release.Name) .Values.opa.deploymentName }}
{{- end }}

{{- define "opa.serviceAccountName" -}}
{{- default (printf "%s-opa" .Release.Name) .Values.opa.serviceAccount.name }}
{{- end }}
