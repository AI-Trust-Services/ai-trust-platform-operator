#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== rollout restart content-serving deployment ==="
sk -n aitrust-msp rollout restart deployment/aitrust-portal-integration 2>&1
sk -n aitrust-msp rollout status deployment/aitrust-portal-integration --timeout=120s 2>&1
echo ""
echo "=== new pod ==="
sk -n aitrust-msp get pods -l app.kubernetes.io/component=portal-integration --show-labels 2>/dev/null
echo ""
echo "=== LIVE served pm-content.json group values after restart ==="
OUT="$STATE/checkd5-content.json"
: > "$OUT"
for i in 1 2 3 4 5; do
  sk -n platform-mesh-system run cd5v$i-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sS http://aitrust-portal.aitrust-msp.svc.cluster.local/pm-content.json 2>/dev/null > "$OUT"
  [ -s "$OUT" ] && grep -q 'trust\.' "$OUT" && break; sleep 4
done
echo "fetched $(wc -c < "$OUT") bytes"
grep -o 'trust\.[a-z.-]*\.msp' "$OUT" | sort | uniq -c
