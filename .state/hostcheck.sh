#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
echo "=== HTTPRoutes for this instance — what hostname(s) do they serve? ==="
sk -n "$GATEWAY_NS" get httproute 2>&1 | grep -av memcache | grep -E 'NAME|25veqwflh7syq7fm|aitp.*-d|^[a-z].*-d-'
echo "--- their hostnames ---"
for r in $(sk -n "$GATEWAY_NS" get httproute -o name 2>/dev/null | grep -E '25veqwflh7syq7fm|aitp'); do
  echo "$r -> $(sk -n "$GATEWAY_NS" get "$r" -o jsonpath='{.spec.hostnames}' 2>/dev/null)"
done
echo "=== the consumer CR status.url (what the portal shows / user clicks) ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 10); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
kc root:orgs:aitrustg2:demo -n default get aitrustplatforminstance d -o jsonpath='status.url={.status.url}{"\n"}' 2>&1 | grep -av memcache
echo "=== so: HTTPRoute host vs APP_PUBLIC_URL host — do they match? ==="
echo "APP_PUBLIC_URL host = 25veqwflh7syq7fm-d.ai-trust-1..."
