#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
OUT=/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/wc.js
sk -n platform-mesh-system run js3-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sSk https://aitrustg2.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/assets/platform-mesh-portal-ui-wc.js 2>/dev/null > "$OUT"
echo "size=$(wc -c < "$OUT")"
echo "=== property read counts ==="
for p in 'kind' 'entity' 'entityKind' 'apiGroup' 'plural' 'entityCollection' 'singular' 'resourceDefinition'; do
  printf "%-18s %s\n" ".$p" "$(grep -oaE "\.$p[^A-Za-z]" "$OUT" 2>/dev/null | wc -l)"
done
echo "=== create<X> + _Input concatenation forms ==="
grep -oaE '"create"\+[A-Za-z0-9_.$]{1,20}' "$OUT" | sort -u | head
grep -oaE '[A-Za-z0-9_.$]{1,20}\+"_Input"' "$OUT" | sort -u | head
grep -oaE '[A-Za-z0-9_.$]{1,20}\+"Input"' "$OUT" | sort -u | head
