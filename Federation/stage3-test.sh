#!/bin/bash
# Stage 3 TEST — create a federated Subscription (simulates a prod-portal Enable) and watch the
# controller provision a fed-<org> tenant ON ai-trust-1. Test org = "fedtest".
set -uo pipefail
FED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="/mnt/c/Claude/projects/eu-ai-trust-prod/Standard_AiTrust_MT_MSP"
source "$BUNDLE/scripts/lib.sh"; load_config
f(){ grep -avi memcache; }
REMOTE_WS="root:providers:ai-trust-remote"
A1="/mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-a1.kubeconfig"
ORG="fedtest"

cp /mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-prod.kubeconfig "$BUNDLE/.state/shoot-kubeconfig.yaml" 2>/dev/null || true
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "=== create a consumer workspace + Subscription (simulating portal Enable) ==="
# Simplest faithful path: create the Subscription in a namespace inside the provider ws that the
# syncagent mirrors down. Portal normally creates it in the consumer account ws; for the test we create
# it directly in the provider ws default ns so the syncagent mirrors it to this shoot.
cat <<EOF | kc "$REMOTE_WS" apply -f - 2>&1 | f
apiVersion: sub.aitrust.remote/v1alpha1
kind: Subscription
metadata: { name: fedtest-sub, namespace: default }
spec:
  displayName: "Fed Test"
  org: "$ORG"
  adminEmail: "fedtest@example.com"
EOF

echo "=== watch: did the syncagent mirror it down to the prod shoot? ==="
for i in $(seq 1 12); do
  n=$(sk get subscriptions.sub.aitrust.remote -A 2>/dev/null | grep -c fedtest || true)
  [ "$n" -ge 1 ] && { echo "  mirrored to shoot:"; sk get subscriptions.sub.aitrust.remote -A 2>&1 | f; break; }
  sleep 5
done

echo "=== controller logs (provisioning fed-$ORG on a1) ==="
POD=$(sk -n aitrust-remote get pod -l app.kubernetes.io/name=aitrust-federation -o name 2>/dev/null | head -1)
sk -n aitrust-remote logs "$POD" --tail=40 2>&1 | f

echo "=== did the tenant-stores Job get stamped ON ai-trust-1? ==="
kubectl --kubeconfig "$A1" -n aitrust-msp get jobs 2>&1 | f | grep -aiE "fed|tenant-stores" || echo "  (none yet)"
echo "=== a1 schemas (expect tenant_fed_fedtest once Job runs) ==="
PGPOD=$(kubectl --kubeconfig "$A1" -n aitrust-msp get pod 2>/dev/null | grep -E "^postgres-" | awk '{print $1}' | head -1)
kubectl --kubeconfig "$A1" -n aitrust-msp exec "$PGPOD" -- bash -lc 'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" -tAc "SELECT nspname FROM pg_namespace WHERE nspname LIKE '"'"'tenant_fed%'"'"'"' 2>&1 | f || echo "  (schema not created yet)"
echo DONE_TEST
