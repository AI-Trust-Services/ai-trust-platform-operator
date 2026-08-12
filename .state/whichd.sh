#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== which HTTPRoutes serve d.ai-trust-1 vs 25veqwflh7syq7fm-d.ai-trust-1 now? ==="
sk -n "$GATEWAY_NS" get httproute 2>&1 | grep -av memcache | grep -E 'NAME|-d-app|-d-keycloak' | grep -iE 'NAME|d\.ai|25veqw'
for r in $(sk -n "$GATEWAY_NS" get httproute -o name 2>/dev/null | grep -E '\-d-'); do
  echo "$r host=$(sk -n "$GATEWAY_NS" get "$r" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null) -> backendNs=$(sk -n "$GATEWAY_NS" get "$r" -o jsonpath='{.spec.rules[0].backendRefs[0].namespace}' 2>/dev/null)"
done
echo ""
echo "=== which instance namespaces exist for 'd'? ==="
sk get ns 2>&1 | grep -av memcache | grep -E 'aitp.*-d$|aitp.*-d '
echo "=== the LIVE instance d: its status.url (the host you SHOULD use) ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 10); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
kc root:orgs:aitrustg2:demo -n default get aitrustplatforminstance d -o jsonpath='status.url={.status.url}  ns={.status.namespace}{"\n"}' 2>&1 | grep -av memcache
