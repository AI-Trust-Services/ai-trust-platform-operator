#!/bin/bash
set -uo pipefail
BUNDLE="/mnt/c/Claude/projects/eu-ai-trust-prod/Standard_AiTrust_MT_MSP"
source "$BUNDLE/scripts/lib.sh"; load_config
f(){ grep -avi memcache; }
ACCT_WS="root:orgs:aitrust:tenant"
A1="/mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-a1.kubeconfig"
PROD="/mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-prod.kubeconfig"
cp "$PROD" "$BUNDLE/.state/shoot-kubeconfig.yaml" 2>/dev/null || true
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "=== roll controller to status-string-fixed image ==="
kubectl --kubeconfig "$PROD" -n aitrust-remote rollout restart deploy/aitrust-federation 2>&1 | f | tail -1
kubectl --kubeconfig "$PROD" -n aitrust-remote rollout status deploy/aitrust-federation --timeout=120s 2>&1 | f | tail -1

echo "=== BEFORE delete: a1 federated resources ==="
echo "  proxy deploy: $(kubectl --kubeconfig "$A1" -n aitrust-msp get deploy oauth2-proxy-fed-fedtest -o name 2>&1 | f)"
echo "  route:        $(kubectl --kubeconfig "$A1" -n platform-mesh-system get httproute aitrust-fed-fedtest -o name 2>&1 | f)"
echo "  schema:       tenant_fed_fedtest (data — must SURVIVE delete)"

echo "=== delete the federated Subscription (simulates Disable) ==="
kc "$ACCT_WS" delete subscriptions.sub.aitrust.remote -n default fedtest-sub 2>&1 | f

echo "=== watch teardown (proxy/route removed; data preserved) ==="
for i in $(seq 1 18); do
  sleep 8
  pr=$(kubectl --kubeconfig "$A1" -n aitrust-msp get deploy oauth2-proxy-fed-fedtest -o name 2>/dev/null)
  rt=$(kubectl --kubeconfig "$A1" -n platform-mesh-system get httproute aitrust-fed-fedtest -o name 2>/dev/null)
  echo "  [$i] proxy='${pr:-gone}' route='${rt:-gone}'"
  [ -z "$pr" ] && [ -z "$rt" ] && break
done

echo "=== AFTER delete: tenant DATA must remain (append-only) ==="
PGPOD=$(kubectl --kubeconfig "$A1" -n aitrust-msp get pod 2>/dev/null | grep -E "^postgres-" | awk '{print $1}' | head -1)
kubectl --kubeconfig "$A1" -n aitrust-msp exec "$PGPOD" -- bash -lc 'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" -tAc "SELECT nspname FROM pg_namespace WHERE nspname = '"'"'tenant_fed_fedtest'"'"'"' 2>&1 | f
echo "  (schema present above = data preserved on Disable ✓)"
echo DONE_TEARDOWN
