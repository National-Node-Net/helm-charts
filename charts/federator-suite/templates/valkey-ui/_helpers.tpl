{{- define "valkeyui.name" -}}
{{- default (printf "%s-valkey-ui" .Release.Name) .Values.valkey.ui.deploymentName }}
{{- end }}
