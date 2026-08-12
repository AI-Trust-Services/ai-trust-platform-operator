#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS=root:orgs:aitrustg2:demo
NS=$(kc "$WS" -n default get aitrustplatforminstance d -o jsonpath='{.status.namespace}' 2>/dev/null)
echo "instance d: phase=$(kc "$WS" -n default get aitrustplatforminstance d -o jsonpath='{.status.phase}' 2>/dev/null) ns=$NS"
[ -z "$NS" ] && NS=$(sk get ns 2>/dev/null | grep -av memcache | grep -oE 'aitp-[a-z0-9]+-d' | head -1)
echo "resolved NS=$NS"
echo "=== not-ready deploys ==="
sk -n "$NS" get deploy --no-headers 2>&1 | grep -av memcache | awk '$2!="1/1"{print "WAIT",$1,$2}'; echo "(none above = all ready)"
echo "=== oauth2-proxy LIVE cookie setting (should be secure:true now, from manifest) ==="
POD=$(sk -n "$NS" get pods 2>/dev/null | grep -av memcache | grep oauth2-proxy | grep Running | awk '{print $1}' | head -1)
sk -n "$NS" logs "$POD" 2>&1 | grep -av memcache | grep -iE 'Cookie settings' | tail -1
echo "=== oauth2 issuer/redeem now /keycloak-prefixed? ==="
sk -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'issuer|redeem|cookie-secure'
