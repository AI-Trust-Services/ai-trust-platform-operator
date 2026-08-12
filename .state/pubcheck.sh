#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== syncagent logs (clean now?) ==="
sk -n aitrust-msp logs deploy/aitrust-syncagent --tail=25 2>&1 | grep -av memcache | tail -25
echo "=== APIResourceSchema in provider ws ==="
kc "$PROVIDER_WS" get apiresourceschema 2>&1 | grep -av memcache | head
echo "=== APIExport spec.resources ==="
kc "$PROVIDER_WS" get apiexport "$EXPORT_NAME" -o jsonpath='{range .spec.resources[*]}{.name}{"\n"}{end}' 2>&1 | grep -av memcache
echo "=== PublishedResource status ==="
sk -n aitrust-msp get publishedresource publish-aitrust-instances -o jsonpath='{.status}{"\n"}' 2>&1 | grep -av memcache | head -c 300; echo
