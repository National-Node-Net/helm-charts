{{- define "opa.serviceAccountName" -}}
{{- default (printf "%s-opa" .Release.Name) .Values.opa.serviceAccount.name }}
{{- end }}



