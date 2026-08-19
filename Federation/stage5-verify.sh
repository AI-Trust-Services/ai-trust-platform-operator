#!/bin/bash
set -uo pipefail
BUNDLE="/mnt/c/Claude/projects/eu-ai-trust-prod/Standard_AiTrust_MT_MSP"
source "$BUNDLE/scripts/lib.sh"; load_config
f(){ grep -avi memcache; }
A1="/mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-a1.kubeconfig"
PROD="/mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-prod.kubeconfig"
cp "$PROD" "$BUNDLE/.state/shoot-kubeconfig.yaml" 2>/dev/null || true
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "############ STAGE 5 VERIFICATION ############"
echo "=== INV1: prod-LOCAL provider intact (sub.aitrust.msp APIExport) ==="
kc root:providers:ai-trust get apiexport sub.aitrust.msp -o name 2>&1 | f
echo "=== INV2: both provider tiles present on prod kcp ==="
echo "  local:     $(kc root:providers:ai-trust get providermetadata sub.aitrust.msp -o jsonpath='{.spec.displayName}' 2>&1 | f)"
echo "  federated: $(kc root:providers:ai-trust-remote get providermetadata sub.aitrust.remote -o jsonpath='{.spec.displayName}' 2>&1 | f)"
echo "=== INV3: a1 NATIVE tenants untouched (schemas still present) ==="
PGPOD=$(kubectl --kubeconfig "$A1" -n aitrust-msp get pod 2>/dev/null | grep -E "^postgres-" | awk '{print $1}' | head -1)
kubectl --kubeconfig "$A1" -n aitrust-msp exec "$PGPOD" -- bash -lc 'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" -tAc "SELECT nspname FROM pg_namespace WHERE nspname LIKE '"'"'tenant_%'"'"' ORDER BY 1"' 2>&1 | f
echo "=== INV4: prod-LOCAL tenants untouched (prod schemas) ==="
PGPODP=$(kubectl --kubeconfig "$PROD" -n aitrust-msp get pod 2>/dev/null | grep -E "^postgres-" | awk '{print $1}' | head -1)
kubectl --kubeconfig "$PROD" -n aitrust-msp exec "$PGPODP" -- bash -lc 'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" -tAc "SELECT nspname FROM pg_namespace WHERE nspname LIKE '"'"'tenant_%'"'"' ORDER BY 1"' 2>&1 | f
echo "=== INV5: federated tenant isolation on a1 (fed-fedtest role wall) ==="
kubectl --kubeconfig "$A1" -n aitrust-msp exec "$PGPODP" -- true 2>/dev/null
kubectl --kubeconfig "$A1" -n aitrust-msp exec "$PGPOD" -- bash -lc 'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" -c "SET ROLE \"t_fed_fedtest\"; SELECT count(*) FROM tenant_fridaytest.ai_systems;" 2>&1' | f | tail -3
echo "  (expect: permission denied for schema tenant_fridaytest)"
echo DONE_VERIFY
