#!/bin/bash
set -uo pipefail
BUNDLE="/mnt/c/Claude/projects/eu-ai-trust-prod/Standard_AiTrust_MT_MSP"
source "$BUNDLE/scripts/lib.sh"; load_config
f(){ grep -avi memcache; }
REMOTE_WS="root:providers:ai-trust-remote"
ACCT_WS="root:orgs:aitrust:tenant"     # the account ws where Subscriptions live (ns default exists)
ORG="fedtest"
A1="/mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-a1.kubeconfig"
cp /mnt/c/claude/projects/eu-ai-trust-prod/.fed_shoot-prod.kubeconfig "$BUNDLE/.state/shoot-kubeconfig.yaml" 2>/dev/null || true
setup_kcp; kcp_portforward
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT

echo "=== 1. bind sub.aitrust.remote in the ACCOUNT ws $ACCT_WS ==="
cat <<EOF | kc "$ACCT_WS" apply -f - 2>&1 | f
apiVersion: apis.kcp.io/v1alpha2
kind: APIBinding
metadata: { name: aitrust-remote }
spec:
  reference:
    export: { path: "$REMOTE_WS", name: sub.aitrust.remote }
EOF
for i in $(seq 1 18); do
  ph=$(kc "$ACCT_WS" get apibinding aitrust-remote -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "  binding phase: $ph"; [ "$ph" = "Bound" ] && break; sleep 5
done

echo "=== 2. create the federated Subscription (ns default) — the faithful portal Enable ==="
cat <<EOF | kc "$ACCT_WS" apply -f - 2>&1 | f
apiVersion: sub.aitrust.remote/v1alpha1
kind: Subscription
metadata: { name: fedtest-sub, namespace: default }
spec: { displayName: "Fed Test", org: "$ORG", adminEmail: "fedtest@example.com" }
EOF

echo "=== 3. syncagent mirrors to prod shoot? (per-consumer ns = cluster id) ==="
for i in $(seq 1 24); do
  sk get subscriptions.sub.aitrust.remote -A 2>/dev/null | grep -qi fedtest && { echo "  MIRRORED:"; sk get subscriptions.sub.aitrust.remote -A 2>&1 | f; break; }
  sleep 5
done

echo "=== 4. controller logs (reconciling fed-fedtest) ==="
POD=$(sk -n aitrust-remote get pod -l app.kubernetes.io/name=aitrust-federation -o name 2>/dev/null | head -1)
sk -n aitrust-remote logs "$POD" --tail=30 2>&1 | f

echo "=== 5. status on the Subscription (phase/cluster/url) ==="
kc "$ACCT_WS" get subscriptions.sub.aitrust.remote -n default fedtest-sub -o jsonpath='{.status}{"\n"}' 2>&1 | f

echo "=== 6. tenant-stores job + schema ON a1 (fed-fedtest) ==="
kubectl --kubeconfig "$A1" -n aitrust-msp get jobs 2>&1 | f | grep -aiE "fedtest" || echo "  (no job yet — likely realm gate: Stage 4 pending)"
echo DONE_E2E2
