#!/bin/bash
# Task B — READ-ONLY external probe: what cert does the live instance host actually serve?
# No cluster access needed — just TLS handshake from outside. Also back up inspected manifests.
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
BK=".state/backup-dnscert"; mkdir -p "$BK"

# Back up the source-of-truth artifacts I inspected (local files → backup dir).
cp config/ingress/gateway-listener-patch.tmpl "$BK/" 2>/dev/null
cp config/ingress/httproute.tmpl "$BK/" 2>/dev/null
cp docs/gardener-managed-dns-cert-reference.md "$BK/" 2>/dev/null
cp prerequisites/tls.crt "$BK/domain-certificate.leaf.crt" 2>/dev/null
cp prerequisites/tls-ca.crt "$BK/domain-certificate.ca.crt" 2>/dev/null
# extract just the ensureWildcardListener + wireIngress funcs for the backup record
sed -n '286,377p' operator/main.go > "$BK/operator-wireIngress.snippet.go" 2>/dev/null
openssl x509 -in prerequisites/tls.crt -noout -text > "$BK/domain-certificate.decoded.txt" 2>/dev/null
echo "backed up:"; ls -la "$BK"

HOSTS=(
  "q3c0weh7suf5hgjk-my-aitrust.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
  "25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
)
for H in "${HOSTS[@]}"; do
  echo "===== $H ====="
  echo "-- DNS A-record (does public DNS resolve?) --"
  getent hosts "$H" 2>/dev/null || nslookup "$H" 2>&1 | grep -iE 'address|name|find' | head -4 || echo "no resolver"
  echo "-- TLS cert served on :443 (5s) --"
  echo | timeout 8 openssl s_client -connect "${H}:443" -servername "$H" 2>/dev/null \
    | openssl x509 -noout -subject -issuer -ext subjectAltName 2>/dev/null \
    || echo "TLS probe failed / unreachable"
done
