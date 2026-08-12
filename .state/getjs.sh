#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
# fetch the portal-ui-wc.js (the generic-list-view web component) and find the create-mutation template
sk -n platform-mesh-system run js-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  sh -c 'curl -sSk https://portal.platform-mesh-system.svc.cluster.local:8080/assets/platform-mesh-portal-ui-wc.js 2>/dev/null || curl -sSk http://portal.platform-mesh-system.svc.cluster.local:8080/assets/platform-mesh-portal-ui-wc.js 2>/dev/null' > "$STATE/wc.js" 2>/dev/null
echo "size: $(wc -c < "$STATE/wc.js")"
echo "=== how the mutation string is built (grep for create + version + Input) ==="
grep -oE 'mutation[^`]{0,120}' "$STATE/wc.js" 2>/dev/null | head -5
grep -oE 'create[A-Za-z$}{.]{0,40}' "$STATE/wc.js" 2>/dev/null | sort -u | head -20
echo "=== _Input type construction ==="
grep -oE '[A-Za-z0-9_$.{}]{0,40}_Input' "$STATE/wc.js" 2>/dev/null | sort -u | head -10
