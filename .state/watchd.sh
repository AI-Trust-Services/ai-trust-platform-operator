#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS=root:orgs:aitrustg2:demo
echo "=== the instance 'd' as the consumer sees it ==="
kc "$WS" -n default get aitrustplatforminstance d -o jsonpath='phase={.status.phase} ready={.status.ready} ns={.status.namespace} url={.status.url}{"\n"}' 2>&1 | grep -av memcache
NS=$(kc "$WS" -n default get aitrustplatforminstance d -o jsonpath='{.status.namespace}' 2>/dev/null)
[ -z "$NS" ] && NS=aitp-aitrustg2-demo-d
echo "=== stamped namespace $NS — deploy readiness ==="
sk -n "$NS" get deploy --no-headers 2>&1 | grep -av memcache | awk '{r=($2=="1/1")?"ok":"WAIT"; print r,$1,$2}' | sort | head -30
echo "=== jobs ==="
sk -n "$NS" get jobs --no-headers 2>&1 | grep -av memcache | head
echo "=== node placement (should be msp-at-big) ==="
sk -n "$NS" get pods -o wide 2>&1 | grep -av memcache | awk 'NR>1{print $7}' | sort -u | head
