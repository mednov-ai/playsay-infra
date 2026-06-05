{{- define "keyboard-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "keyboard-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" (include "keyboard-service.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "keyboard-service.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "keyboard-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "keyboard-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keyboard-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "keyboard-service.buildLabels" -}}
playsay.io/build-name: {{ .Values.build.name | quote }}
playsay.io/build-number: {{ .Values.build.number | quote }}
playsay.io/source-branch: {{ .Values.build.branchLabel | quote }}
playsay.io/source-commit: {{ .Values.build.commitShort | quote }}
{{- end -}}

{{- define "keyboard-service.buildAnnotations" -}}
playsay.io/build-name: {{ .Values.build.name | quote }}
playsay.io/source-branch: {{ .Values.build.branch | quote }}
playsay.io/source-commit: {{ .Values.build.commit | quote }}
{{- end -}}
