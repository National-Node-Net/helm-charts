{{- define "kafkaui.name" -}}
{{- default (printf "%s-kafka-ui" .Release.Name) .Values.kafka.ui.deploymentName }}
{{- end }}