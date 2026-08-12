#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"
echo "=== nodes now ==="
sk get nodes -L workload 2>&1 | grep -av memcache | grep -E 'NAME|msp'
echo "=== delete the churning instance (finalizer cleans ns + routes) ==="
kc "$WS" -n default delete aitrustplatforminstance my-aitrust --wait=false 2>&1 | grep -av memcache
echo "=== force-delete leftover instance namespace + its stuck pods ==="
sk delete ns aitp-q3c0weh7suf5hgjk-my-aitrust --wait=false 2>&1 | grep -av memcache
echo "waiting for CR + ns to clear…"
for i in $(seq 1 20); do
  kc "$WS" -n default get aitrustplatforminstance my-aitrust >/dev/null 2>&1 || { echo "CR gone"; break; }
  sleep 6
done
echo "=== recreate fresh (will land on the 128Gi node) ==="
kc "$WS" -n default apply -f - <<EOF 2>&1 | grep -av memcache
apiVersion: trust.ai-trust.msp/v1alpha1
kind: AITrustPlatformInstance
metadata: { name: my-aitrust }
spec: { displayName: "AI Trust — tenant", sizeClass: standard, adminEmail: ${DEMO_USER} }
EOF
echo "recreated"
