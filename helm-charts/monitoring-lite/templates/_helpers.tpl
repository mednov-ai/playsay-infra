{{- define "monitoring-lite.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "monitoring-lite.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "monitoring-lite.name" . -}}
{{- end -}}
{{- end -}}

{{- define "monitoring-lite.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "monitoring-lite.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "monitoring-lite.componentLabels" -}}
{{- include "monitoring-lite.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "monitoring-lite.vmUrl" -}}
http://{{ include "monitoring-lite.fullname" . }}-victoria-metrics:{{ .Values.victoriaMetrics.service.port }}
{{- end -}}

{{- define "monitoring-lite.alertmanagerUrl" -}}
http://{{ include "monitoring-lite.fullname" . }}-alertmanager:{{ .Values.alertmanager.service.port }}
{{- end -}}
