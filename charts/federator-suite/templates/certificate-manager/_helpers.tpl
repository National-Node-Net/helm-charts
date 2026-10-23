{{- define "certificateManager.name" -}}
{{ default (printf "%s-federator-certificate-manager" .Release.Name) .Values.certificateManager.deploymentName }}
{{- end -}}

{{- define "certificateManager.serviceAccountName" -}}
{{ default (printf "%s-federator-certificate-manager" .Release.Name) .Values.certificateManager.serviceAccount.name }}
{{- end -}}

{{- define "certificateManager.claimName" -}}
{{ default  (printf "%s-federator-certificate-manager" .Release.Name) .Values.certificateManager.persistence.name }}
{{- end -}}
