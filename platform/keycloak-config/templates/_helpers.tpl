{{- define "keycloak-config.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "keycloak-config.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "keycloak-config.labels" -}}
app.kubernetes.io/name: {{ include "keycloak-config.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: platform
{{- end -}}

{{- define "keycloak-config.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak-config.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "keycloak-config.realmConfigName" -}}
{{- printf "%s-realm" (include "keycloak-config.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
