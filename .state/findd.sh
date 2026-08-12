#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
# wait for port-forward readiness
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS=root:orgs:aitrustg2:demo
echo "=== all AITrustPlatformInstances in the account (all namespaces) ==="
kc "$WS" get aitrustplatforminstance -A 2>&1 | grep -av memcache | head
echo "=== shoot-side: any mirrored CR + any aitp-* namespace ==="
sk get aitrustplatforminstance -A 2>&1 | grep -av memcache | head
sk get ns 2>&1 | grep -av memcache | grep -E 'aitp-|NAME' | head
echo "=== operator log tail (did it see a new CR / any error?) ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=20 2>&1 | grep -av memcache \
  | grep -ivE '/src/main|controller-runtime@|sigs.k8s.io|Starting' | tail -10
