{{- define "kafka.name" -}}
{{- default (printf "%s" .Release.Name) .Values.kafka.deploymentName }}
{{- end }}

{{- define "kafka.bootstrapServers" -}}
{{- if .Values.kafka.external -}}
{{- .Values.kafka.externalSettings.bootstrapServers -}}
{{- else -}}
{{- printf "%s-kafka-kafka-bootstrap.%s.svc.cluster.local:9092" (include "kafka.name" .) .Release.Namespace -}}
{{- end -}}
{{- end }}
