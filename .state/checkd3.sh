#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== ConfigMap group values (ns aitrust-msp) ==="
sk -n aitrust-msp get configmap aitrust-portal-config -o jsonpath='{.data}' 2>/dev/null | grep -o 'trust\.[a-z.-]*\.msp' | sort | uniq -c
echo ""
echo "=== content pod age/status (ns aitrust-msp) ==="
sk -n aitrust-msp get pods -l app=aitrust-portal-integration -o wide 2>/dev/null
echo ""
echo "=== LIVE served pm-content.json group values ==="
OUT="$STATE/checkd3-content.json"
: > "$OUT"
for i in 1 2 3; do
  sk -n platform-mesh-system run cd3v$i-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sS http://aitrust-portal.aitrust-msp.svc.cluster.local/pm-content.json 2>/dev/null > "$OUT"
  [ -s "$OUT" ] && break; sleep 3
done
echo "fetched $(wc -c < "$OUT") bytes"
grep -o 'trust\.[a-z.-]*\.msp' "$OUT" | sort | uniq -c
