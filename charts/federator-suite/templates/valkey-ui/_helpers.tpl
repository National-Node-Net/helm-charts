{{- define "valkeyui.name" -}}
{{- default (printf "%s-valkey-ui" .Release.Name) .Values.valkeyUi.deploymentName }}
{{- end }}