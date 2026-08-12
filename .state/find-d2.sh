#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/find-d2.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done

echo "=== enumerate ALL org workspaces, then all sub-workspaces, hunting every AITrustPlatformInstance ==="
ORGS=$(kc root:orgs get workspace -o name 2>/dev/null | grep -av memcache | sed 's#workspace.tenancy.kcp.io/##')
for org in $ORGS; do
  subs=$(kc "root:orgs:$org" get workspace -o name 2>/dev/null | grep -av memcache | sed 's#workspace.tenancy.kcp.io/##')
  for sub in $subs; do
    WS="root:orgs:$org:$sub"
    out=$(kc "$WS" -n default get aitrustplatforminstance -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,URL:.status.url' 2>/dev/null | grep -av memcache | grep -v '^NAME')
    [ -n "$out" ] && echo "$WS => $out"
  done
done
echo "--- which one resolves to host 33hins0iklcwfg45 (the namespace prefix = first 16 chars of the consumer ws cluster id)? that's the CR to delete ---"
echo DONE
