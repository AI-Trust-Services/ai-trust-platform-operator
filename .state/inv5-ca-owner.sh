#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/inv5-ca-owner.out 2>&1
K(){ kubectl "$@" 2>&1 | grep -avi memcache; }

echo "############ Decode the pinned CA from the WAC (subject/issuer/dates) ############"
cat > /tmp/wac-ca.pem <<'PEM'
-----BEGIN CERTIFICATE-----
MIIDNTCCAh2gAwIBAgIULXjNvdjr5NFFtopXpmr26ixpLLgwDQYJKoZIhvcNAQEL
BQAwKjEoMCYGA1UEAwwfU3RhbmRhcmQgUGxhdGZvcm0gTWVzaCBMb2NhbCBDQTAe
Fw0yNjA4MTAxMTE5MDhaFw0yODExMTIxMTE5MDhaMCoxKDAmBgNVBAMMH1N0YW5k
YXJkIFBsYXRmb3JtIE1lc2ggTG9jYWwgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IB
DwAwggEKAoIBAQDCzzrIn244EO+Pejof2D1F9EYm+zvhahyVTzyDdL3fBopQ6q9c
jhMqInqQb6Gk8XpemPJMvBPFAyuT+DCi55OGg0QOTuBsicB7ai9RIC9rrKXy8YUs
2dmRIHaGJb4Q5VU5H7B9MoxJMONgHJ19LONmrbR8X8PvTMBPUlEfKV2KVMhjXXtp
46vyCgbL+KGWY/f1OKIHDhJM7NpuJDkybi0RYWaIZuRl2erOgcme7POptWOCcZ0/
Npv1RFeqW5S6lKfqA+XW2tVIUEVwCL5X5By2kmEAdCQ3iSDr/+3fXRH4T0DSz4wr
SSXyINSv5rCxBIxgqX1RnLiI7ePEKCyGw4fnAgMBAAGjUzBRMB0GA1UdDgQWBBRb
Dey0rQOdQrtiqaZIeg1XRvmBUDAfBgNVHSMEGDAWgBRbDey0rQOdQrtiqaZIeg1X
RvmBUDAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQAleIXFiTxx
RtYHE6o7XMMcZQEuWG7t/4mUG28C60FDXoWwQQNJ+FBXxgkUPB60PclVKDStWHn5
hE6qNomhd78cvQHdOS/L3p14VypUevswPAe5/UGyryqVraqoZss0KmUGoJgPvQVU
bZJdE0tj5XW8n3EexrZ0nWwTCt086/yVpJzmncuEeuZkk+nRVG6WoJLXcVoY4zlx
Oic+OXQIBoT+Umgrp2ohcr/5ibLzEyPpATYrHDhebi5T+TiOizY44cTxUZrFPUDC
S4fQyiskOa+S28MOdofQik294hGL/PrrZ64X1EQHpdkno4D3y0Kk3KjRvrRPgBRU
kEeUb1ZMoe6j
-----END CERTIFICATE-----
PEM
openssl x509 -in /tmp/wac-ca.pem -noout -subject -issuer -dates -fingerprint 2>&1 || echo "(no local openssl)"

echo; echo "############ Currently-served gateway cert secret 'domain-certificate' CA ############"
K -n "$MESH_NS" get secret domain-certificate -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d > /tmp/gw-ca.pem 2>/dev/null
if [ -s /tmp/gw-ca.pem ]; then openssl x509 -in /tmp/gw-ca.pem -noout -subject -issuer -fingerprint 2>&1; else echo "(no ca.crt in domain-certificate)"; fi
echo "--- tls.crt leaf of domain-certificate ---"
K -n "$MESH_NS" get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/gw-leaf.pem 2>/dev/null
openssl x509 -in /tmp/gw-leaf.pem -noout -subject -issuer 2>&1 | head

echo; echo "############ LE cert secret 'cert-aitrust-full' issuer ############"
K -n "$MESH_NS" get secret cert-aitrust-full -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/le-leaf.pem 2>/dev/null
openssl x509 -in /tmp/le-leaf.pem -noout -subject -issuer 2>&1 | head

echo; echo "############ WHO OWNS the WAC objects? iam-service / onboarding ############"
K -n "$MESH_NS" get deploy | grep -iE 'iam|onboard|account|tenant'
echo "--- iam-service configmaps/secrets ---"
K -n "$MESH_NS" get cm,secret | grep -iE 'iam|onboard|account-operator|kcp-tenant'
