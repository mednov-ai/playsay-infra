{{- define "worksheet-import-service.name" -}}worksheet-import-service{{- end }}
{{- define "worksheet-import-service.fullname" -}}{{ include "worksheet-import-service.name" . }}{{- end }}
{{- define "worksheet-import-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "worksheet-import-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{- define "worksheet-import-service.labels" -}}
{{ include "worksheet-import-service.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
