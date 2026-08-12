#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== portal service name/port ==="
sk -n "$MESH_NS" get svc | grep -av memcache | grep -iE 'NAME|portal'
echo "=== fetch the wc.js via the public host (has the asset) ==="
sk -n platform-mesh-system run js2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sSk https://aitrustg2.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/assets/platform-mesh-portal-ui-wc.js > "$STATE/wc.js" 2>/dev/null
echo "size: $(wc -c < "$STATE/wc.js")"
head -c 120 "$STATE/wc.js"; echo
