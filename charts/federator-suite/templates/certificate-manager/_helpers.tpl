{{- define "certificateManager.name" -}}
{{ default "federator-certificate-manager" .Values.certificateManager.deploymentName }}
{{- end -}}

{{- define "certificateManager.serviceAccountName" -}}
{{ default (include "certificateManager.name" .) .Values.certificateManager.serviceAccount.name }}
{{- end -}}

{{- define "certificateManager.claimName" -}}
{{ default (include "certificateManager.name" .) .Values.certificateManager.persistence.name }}
{{- end -}}

