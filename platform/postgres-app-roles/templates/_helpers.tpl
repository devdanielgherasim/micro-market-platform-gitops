{{- define "postgres-app-roles.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "postgres-app-roles.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "postgres-app-roles.labels" -}}
app.kubernetes.io/name: {{ include "postgres-app-roles.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: platform
{{- end -}}

{{- define "postgres-app-roles.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgres-app-roles.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "postgres-app-roles.scriptConfigMapName" -}}
{{- printf "%s-script" (include "postgres-app-roles.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
