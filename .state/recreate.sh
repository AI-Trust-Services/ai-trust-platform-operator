#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
WS="root:orgs:$ORG_NAME:$ACCOUNT_NAME"
echo "=== wait for old CR fully gone ==="
for i in $(seq 1 15); do
  kc "$WS" -n default get aitrustplatforminstance my-aitrust >/dev/null 2>&1 || { echo "gone"; break; }
  sleep 4
done
echo "=== recreate ==="
kc "$WS" -n default apply -f - <<EOF 2>&1 | grep -av memcache
apiVersion: trust.ai-trust.msp/v1alpha1
kind: AITrustPlatformInstance
metadata: { name: my-aitrust }
spec: { displayName: "AI Trust — tenant", sizeClass: standard, adminEmail: ${DEMO_USER} }
EOF
echo "=== watch new namespace + status (correct host) ==="
for i in $(seq 1 12); do
  ST=$(kc "$WS" -n default get aitrustplatforminstance my-aitrust -o jsonpath='{.status.phase}/{.status.ready} {.status.url}' 2>/dev/null)
  echo "  $ST"
  echo "$ST" | grep -q "Ready/true" && { echo ">>> READY <<<"; break; }
  sleep 20
done
