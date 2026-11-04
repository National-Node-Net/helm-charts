{{- define "valkey.hostname" -}}
{{- if .Values.valkey.external -}}
{{- .Values.valkey.externalSettings.host -}}
{{- else -}}
{{- printf "%s-valkey" .Release.Name -}}
{{- end -}}
{{- end -}}
