{{- define "game-adapter-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "game-adapter-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "game-adapter-service.name" . | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "game-adapter-service.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "game-adapter-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "game-adapter-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "game-adapter-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "game-adapter-service.buildLabels" -}}
playsay.io/build-name: {{ .Values.build.name | quote }}
playsay.io/build-number: {{ .Values.build.number | quote }}
playsay.io/source-branch: {{ .Values.build.branchLabel | quote }}
playsay.io/source-commit: {{ .Values.build.commitShort | quote }}
{{- end -}}
