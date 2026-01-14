{{/*
Expand the name of the chart.
*/}}
{{- define "ocserv.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ocserv.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ocserv.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ocserv.labels" -}}
helm.sh/chart: {{ include "ocserv.chart" . }}
{{ include "ocserv.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ocserv.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ocserv.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ocserv.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ocserv.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get VPN network address from CIDR
*/}}
{{- define "ocserv.vpn.ipv4Network" -}}
{{- $cidr := .Values.network.vpn.cidr | default "10.7.7.0/24" -}}
{{- $parts := splitList "/" $cidr -}}
{{- $network := index $parts 0 -}}
{{- $network | quote -}}
{{- end }}

{{/*
Get VPN netmask from CIDR prefix
*/}}
{{- define "ocserv.vpn.ipv4Netmask" -}}
{{- $cidr := .Values.network.vpn.cidr | default "10.7.7.0/24" -}}
{{- $parts := splitList "/" $cidr -}}
{{- $prefix := int (index $parts 1) -}}
{{- if eq $prefix 32 }}{{- "255.255.255.255" | quote -}}
{{- else if eq $prefix 31 }}{{- "255.255.255.254" | quote -}}
{{- else if eq $prefix 30 }}{{- "255.255.255.252" | quote -}}
{{- else if eq $prefix 29 }}{{- "255.255.255.248" | quote -}}
{{- else if eq $prefix 28 }}{{- "255.255.255.240" | quote -}}
{{- else if eq $prefix 27 }}{{- "255.255.255.224" | quote -}}
{{- else if eq $prefix 26 }}{{- "255.255.255.192" | quote -}}
{{- else if eq $prefix 25 }}{{- "255.255.255.128" | quote -}}
{{- else if eq $prefix 24 }}{{- "255.255.255.0" | quote -}}
{{- else if eq $prefix 23 }}{{- "255.255.254.0" | quote -}}
{{- else if eq $prefix 22 }}{{- "255.255.252.0" | quote -}}
{{- else if eq $prefix 21 }}{{- "255.255.248.0" | quote -}}
{{- else if eq $prefix 20 }}{{- "255.255.240.0" | quote -}}
{{- else if eq $prefix 19 }}{{- "255.255.224.0" | quote -}}
{{- else if eq $prefix 18 }}{{- "255.255.192.0" | quote -}}
{{- else if eq $prefix 17 }}{{- "255.255.128.0" | quote -}}
{{- else if eq $prefix 16 }}{{- "255.255.0.0" | quote -}}
{{- else if eq $prefix 15 }}{{- "254.0.0.0" | quote -}}
{{- else if eq $prefix 14 }}{{- "252.0.0.0" | quote -}}
{{- else if eq $prefix 13 }}{{- "248.0.0.0" | quote -}}
{{- else if eq $prefix 12 }}{{- "240.0.0.0" | quote -}}
{{- else if eq $prefix 11 }}{{- "224.0.0.0" | quote -}}
{{- else if eq $prefix 10 }}{{- "192.0.0.0" | quote -}}
{{- else if eq $prefix 9 }}{{- "255.128.0.0" | quote -}}
{{- else if eq $prefix 8 }}{{- "255.0.0.0" | quote -}}
{{- else if eq $prefix 7 }}{{- "254.0.0.0" | quote -}}
{{- else if eq $prefix 6 }}{{- "252.0.0.0" | quote -}}
{{- else if eq $prefix 5 }}{{- "248.0.0.0" | quote -}}
{{- else if eq $prefix 4 }}{{- "240.0.0.0" | quote -}}
{{- else if eq $prefix 3 }}{{- "224.0.0.0" | quote -}}
{{- else if eq $prefix 2 }}{{- "192.0.0.0" | quote -}}
{{- else if eq $prefix 1 }}{{- "128.0.0.0" | quote -}}
{{- else }}{{- "0.0.0.0" | quote -}}
{{- end }}
{{- end }}

{{/*
Generate ocpasswd entry for single user
*/}}
{{- define "ocserv.user.generateEntry" -}}
{{- $username := .username -}}
{{- $password := .password -}}
{{- $salt := randAlphaNum 16 -}}
{{- $combined := printf "%s%s" $password $salt -}}
{{- $hash := $combined | sha256sum -}}
{{- printf "%s:*:$5$%s$%s" $username $salt $hash -}}
{{- end }}

{{/*
Generate ocpasswd file content
*/}}
{{- define "ocserv.user.ocpasswdContent" -}}
{{- if .Values.users.credentials -}}
{{- .Values.users.credentials -}}
{{- else if .Values.users.list -}}
{{- $first := true -}}
{{- range $user := .Values.users.list -}}
{{- if not $first -}}
{{- "\n" -}}{{- end -}}
{{- include "ocserv.user.generateEntry" $user -}}
{{- $first = false -}}
{{- end -}}
{{- else if and .Values.users.username .Values.users.password -}}
{{- $user := dict "username" .Values.users.username "password" .Values.users.password -}}
{{- include "ocserv.user.generateEntry" $user -}}
{{- else -}}
{{- fail "Either users.credentials or users.list must be provided" -}}
{{- end }}
{{- end }}

{{/*
Generate smart route injector script for DaemonSet
*/}}
{{- define "ocserv.routeInjector.daemonScript" -}}
set -e
echo "[INFO] Enable IP forwarding"
sysctl -w net.ipv4.ip_forward=1 || true

# Network configuration (static values rendered from values.yaml)
POD_CIDR="{{ .Values.network.podCidr }}"
VPN_CIDR="{{ .Values.network.vpn.cidr }}"
# OCSERV Pod IP will be passed as environment variable

echo "[INFO] POD_CIDR: $POD_CIDR"
echo "[INFO] VPN_CIDR: $VPN_CIDR"
echo "[INFO] OCSERV_POD_IP: $OCSERV_POD_IP"

# Insert NAT exemption for POD_CIDR -> VPN_CIDR (to allow pods to reach VPN clients)
echo "[INFO] Insert NAT exemption for $POD_CIDR -> $VPN_CIDR"
if ! iptables -t nat -C POSTROUTING -s "$POD_CIDR" -d "$VPN_CIDR" -j RETURN 2>/dev/null; then
  iptables -t nat -I POSTROUTING 1 -s "$POD_CIDR" -d "$VPN_CIDR" -j RETURN || true
fi

# Setup route to VPN network via OCSERV Pod (only route needed on nodes)
echo "[INFO] Setting up route to VPN network via OCSERV Pod..."
if ip route | grep -q "$VPN_CIDR via $OCSERV_POD_IP"; then
  echo "[INFO] VPN route already exists"
else
  echo "[INFO] Adding VPN route: $VPN_CIDR via $OCSERV_POD_IP"
  ip route del $VPN_CIDR 2>/dev/null || true
  ip route add $VPN_CIDR via $OCSERV_POD_IP || true
fi

echo "[INFO] Route setup completed"
sleep infinity
{{- end }}