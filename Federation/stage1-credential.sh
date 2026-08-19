#!/bin/bash
# stage1-credential.sh — create the scoped ServiceAccount on the PROVIDER cluster, build a kubeconfig
# from its long-lived token, and store it as Secret aitrust-1-shoot-kubeconfig in the CONSUMER ns
# aitrust-remote. Idempotent. Called by install-federation.sh (Stage 1).
#
# Env in:
#   PROVIDER_KUBECONFIG  — kubeconfig for the provider cluster (ai-trust-1)  [required]
#   CONSUMER_KUBECONFIG  — kubeconfig for the consumer cluster (ai-trust-prod) [required]
#   PROVIDER_NS          — ns on the provider where the app runs (default aitrust-msp)
#   GATEWAY_NS           — provider gateway ns (default platform-mesh-system)
set -uo pipefail
f(){ grep -avi memcache; }
export PATH="${PATH}:/usr/local/bin:/usr/bin:/bin"
FED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROVIDER_KUBECONFIG:?set PROVIDER_KUBECONFIG}"
: "${CONSUMER_KUBECONFIG:?set CONSUMER_KUBECONFIG}"
: "${PROVIDER_NS:=aitrust-msp}"
SA_OUT="${SA_OUT:-/tmp/aitrust-federation-sa.kubeconfig}"

echo "== Stage 1: provider SA + RBAC =="
kubectl --kubeconfig "$PROVIDER_KUBECONFIG" apply -f "$FED/stage1-a1-serviceaccount.yaml" 2>&1 | f

echo "== waiting for SA token =="
tok=""
for i in $(seq 1 15); do
  tok=$(kubectl --kubeconfig "$PROVIDER_KUBECONFIG" -n "$PROVIDER_NS" get secret aitrust-federation-token \
        -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)
  [ -n "$tok" ] && break; sleep 2
done
[ -n "$tok" ] || { echo "  ERROR: SA token not populated"; exit 1; }

API=$(kubectl --kubeconfig "$PROVIDER_KUBECONFIG" config view -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl --kubeconfig "$PROVIDER_KUBECONFIG" -n "$PROVIDER_NS" get secret aitrust-federation-token -o jsonpath='{.data.ca\.crt}')
cat > "$SA_OUT" <<EOF
apiVersion: v1
kind: Config
clusters: [{ name: provider, cluster: { server: ${API}, certificate-authority-data: ${CA} } }]
contexts: [{ name: fed, context: { cluster: provider, user: aitrust-federation, namespace: ${PROVIDER_NS} } }]
current-context: fed
users: [{ name: aitrust-federation, user: { token: ${tok} } }]
EOF
echo "  built provider SA kubeconfig → $SA_OUT"

echo "== verify least-privilege =="
echo "  create jobs (msp):        $(kubectl --kubeconfig "$SA_OUT" auth can-i create jobs -n "$PROVIDER_NS" 2>&1 | f)"
echo "  create httproutes (gw):   $(kubectl --kubeconfig "$SA_OUT" auth can-i create httproutes.gateway.networking.k8s.io -n platform-mesh-system 2>&1 | f)"
echo "  get nodes (expect no):    $(kubectl --kubeconfig "$SA_OUT" auth can-i get nodes 2>&1 | f | tail -1)"

echo "== store on consumer (ns aitrust-remote / Secret aitrust-1-shoot-kubeconfig) =="
kubectl --kubeconfig "$CONSUMER_KUBECONFIG" create namespace aitrust-remote --dry-run=client -o yaml 2>/dev/null \
  | kubectl --kubeconfig "$CONSUMER_KUBECONFIG" apply -f - 2>&1 | f
kubectl --kubeconfig "$CONSUMER_KUBECONFIG" -n aitrust-remote create secret generic aitrust-1-shoot-kubeconfig \
  --from-file=kubeconfig="$SA_OUT" --dry-run=client -o yaml 2>/dev/null \
  | kubectl --kubeconfig "$CONSUMER_KUBECONFIG" apply -f - 2>&1 | f
echo "  stored. Stage 1 done."
