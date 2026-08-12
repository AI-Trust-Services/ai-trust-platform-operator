#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/find-d.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }

echo "=== shoot-side mirrored CRs (name / ns / status.url) — read only ==="
kubectl get aitrustplatforminstance -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,URL:.status.url' 2>&1 | grep -av memcache

echo
echo "=== the consumer WORKSPACES + CRs (source of truth — deleting HERE triggers finalizer teardown) ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
for WS in root:orgs:aitrustg2:demo root:orgs:mirceatest3:accounttest root:orgs:aitrustg2:accounttest; do
  echo "-- $WS --"
  kc "$WS" -n default get aitrustplatforminstance -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,URL:.status.url' 2>&1 | grep -av memcache | head
done
echo DONE
