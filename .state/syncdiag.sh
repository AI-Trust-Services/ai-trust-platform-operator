#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh
load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== syncagent pod state ==="
sk -n aitrust-msp get pods 2>&1 | grep -v memcache | head
echo "=== syncagent logs (last 40) ==="
sk -n aitrust-msp logs deploy/aitrust-syncagent --tail=40 2>&1 | grep -av memcache | tail -40
echo "=== PublishedResource on the shoot ==="
sk -n aitrust-msp get publishedresource 2>&1 | grep -av memcache | head
echo "=== APIExport spec.resources ==="
kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" -o jsonpath='{.spec.resources}{"\n"}' 2>&1 | head
echo "=== APIResourceSchema in provider ws ==="
kc "$PROVIDER_WS" get apiresourceschema 2>&1 | grep -av memcache | head
