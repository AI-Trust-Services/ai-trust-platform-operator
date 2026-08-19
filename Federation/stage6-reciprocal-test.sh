#!/bin/bash
set -uo pipefail
BUNDLE="/mnt/c/Claude/projects/eu-ai-trust-prod/Standard_AiTrust_MT_MSP"
source "$BUNDLE/scripts/lib.sh"; load_config
f(){ grep -avi memcache; }
REMOTE_WS="root:providers:ai-trust-remote"
ACCT_WS="root:orgs:aitrust:tenant"    # accessible + real prod realm 'aitrust'
ORG="aitrust"
A1="/mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-a1.kubeconfig"
PROD="/mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-prod.kubeconfig"
cp "$PROD" "$BUNDLE/.state/shoot-kubeconfig.yaml" 2>/dev/null || true
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "=== controller health ==="
kubectl --kubeconfig "$PROD" -n aitrust-remote get pods 2>&1 | f | grep -aiE "federation|NAME"
POD=$(kubectl --kubeconfig "$PROD" -n aitrust-remote get pod -l app.kubernetes.io/name=aitrust-federation -o name 2>/dev/null | head -1)
kubectl --kubeconfig "$PROD" -n aitrust-remote logs "$POD" --tail=6 2>&1 | f | tail -6

echo "=== does prod realm 'aitrust' exist? (needed for reciprocal client) ==="
KCPOD=$(kubectl --kubeconfig "$PROD" -n platform-mesh-system get pod 2>/dev/null | grep -aiE "^keycloak-[0-9a-f]" | awk '{print $1}' | head -1)
kubectl --kubeconfig "$PROD" -n platform-mesh-system exec "$KCPOD" -- bash -lc '
U=${KEYCLOAK_ADMIN:-${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}}; P=${KEYCLOAK_ADMIN_PASSWORD:-${KC_BOOTSTRAP_ADMIN_PASSWORD:-admin}}
T=$(curl -s http://localhost:8080/keycloak/realms/master/protocol/openid-connect/token -d grant_type=password -d client_id=admin-cli -d "username=$U" -d "password=$P" | sed -n "s/.*\"access_token\":\"\([^\"]*\)\".*/\1/p")
for r in aitrust demo demo-aitrust; do echo -n "  realm $r: "; curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $T" http://localhost:8080/keycloak/admin/realms/$r; done
' 2>&1 | f | grep -aiE "realm "
echo "=== bind + create federated Subscription for aitrust ==="
kc "$ACCT_WS" get apibinding aitrust-remote >/dev/null 2>&1 || cat <<EOF | kc "$ACCT_WS" apply -f - 2>&1 | f
apiVersion: apis.kcp.io/v1alpha2
kind: APIBinding
metadata: { name: aitrust-remote }
spec: { reference: { export: { path: "$REMOTE_WS", name: sub.aitrust.remote } } }
EOF
for i in $(seq 1 12); do [ "$(kc "$ACCT_WS" get apibinding aitrust-remote -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && break; sleep 5; done
cat <<EOF | kc "$ACCT_WS" apply -f - 2>&1 | f
apiVersion: sub.aitrust.remote/v1alpha1
kind: Subscription
metadata: { name: aitrust-fed-sub, namespace: default }
spec: { displayName: "AITrust Fed", org: "$ORG", adminEmail: "aitrust@example.com" }
EOF
echo "=== watch to Ready ==="
for i in $(seq 1 30); do
  sleep 10
  ph=$(kc "$ACCT_WS" get subscriptions.sub.aitrust.remote -n default aitrust-fed-sub -o jsonpath='{.status.phase}' 2>/dev/null)
  msg=$(kc "$ACCT_WS" get subscriptions.sub.aitrust.remote -n default aitrust-fed-sub -o jsonpath='{.status.conditions[0].message}' 2>/dev/null)
  echo "  [$i] $ph — $msg"
  [ "$ph" = "Ready" ] && break
done
echo "=== reciprocal prod-client Job + client in prod realm aitrust ==="
kubectl --kubeconfig "$PROD" -n aitrust-remote get jobs 2>&1 | f | grep -ai "kc-prod-client-fed-aitrust" || echo "  (no prod-client job)"
PP=$(kubectl --kubeconfig "$PROD" -n aitrust-remote get pod 2>/dev/null | grep -ai "kc-prod-client-fed-aitrust" | awk '{print $1}' | head -1)
[ -n "$PP" ] && kubectl --kubeconfig "$PROD" -n aitrust-remote logs "$PP" --tail=12 2>&1 | f
echo DONE
