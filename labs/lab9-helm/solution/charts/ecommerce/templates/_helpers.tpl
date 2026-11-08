{{- define "ecommerce.name" -}}
{{- printf "%s-ecommerce" .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}
{{- define "ecommerce.postgres" -}}
{{- if .Values.postgres.enabled -}}
{{- printf "%s-postgres" (include "ecommerce.name" .) -}}
{{- else -}}
{{- required "postgres.host is required when postgres.enabled=false" .Values.postgres.host -}}
{{- end -}}
{{- end -}}
