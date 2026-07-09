{{- define "keycloak-dns.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "keycloak-dns.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "keycloak-dns.labels" -}}
app.kubernetes.io/name: {{ include "keycloak-dns.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: platform
{{- end -}}

{{- define "keycloak-dns.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak-dns.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
