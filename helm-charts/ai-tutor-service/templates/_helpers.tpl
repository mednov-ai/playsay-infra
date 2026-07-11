{{- define "ai-tutor-service.fullname" -}}{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}{{- end -}}
{{- define "ai-tutor-service.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
{{- define "ai-tutor-service.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
