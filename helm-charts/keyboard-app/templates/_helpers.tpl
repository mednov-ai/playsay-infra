{{- define "keyboard-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "keyboard-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" (include "keyboard-app.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "keyboard-app.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "keyboard-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "keyboard-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keyboard-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "keyboard-app.buildLabels" -}}
playsay.io/build-name: {{ .Values.build.name | quote }}
playsay.io/build-number: {{ .Values.build.number | quote }}
playsay.io/source-branch: {{ .Values.build.branchLabel | quote }}
playsay.io/source-commit: {{ .Values.build.commitShort | quote }}
{{- end -}}

{{- define "keyboard-app.buildAnnotations" -}}
playsay.io/build-name: {{ .Values.build.name | quote }}
playsay.io/source-branch: {{ .Values.build.branch | quote }}
playsay.io/source-commit: {{ .Values.build.commit | quote }}
{{- end -}}
