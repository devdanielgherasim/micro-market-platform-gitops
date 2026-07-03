{{- define "external-secrets-config.remoteKey" -}}
{{- $provider := .root.Values.global.cloudProvider -}}
{{- if eq $provider "aws" -}}
{{- printf "%s/%s" .root.Values.aws.secretPrefix .name -}}
{{- else if eq $provider "gcp" -}}
{{- printf "%s-%s" .root.Values.gcp.secretPrefix .name -}}
{{- else -}}
{{- .name -}}
{{- end -}}
{{- end -}}
