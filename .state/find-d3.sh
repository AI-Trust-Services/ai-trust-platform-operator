#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/find-d3.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done

echo "=== deep 3-level workspace walk: list EVERY AITrustPlatformInstance + its home workspace ==="
ORGS=$(kc root:orgs get workspace -o name 2>/dev/null | grep -av memcache | sed 's#.*/##')
for org in $ORGS; do
  L1=$(kc "root:orgs:$org" get workspace -o name 2>/dev/null | grep -av memcache | sed 's#.*/##')
  for a in $L1; do
    for WS in "root:orgs:$org:$a" ; do
      out=$(kc "$WS" -n default get aitrustplatforminstance -o name 2>/dev/null | grep -av memcache)
      [ -n "$out" ] && echo "$WS  :: $out"
      # one level deeper
      L2=$(kc "$WS" get workspace -o name 2>/dev/null | grep -av memcache | sed 's#.*/##')
      for b in $L2; do
        WS2="$WS:$b"
        out2=$(kc "$WS2" -n default get aitrustplatforminstance -o name 2>/dev/null | grep -av memcache)
        [ -n "$out2" ] && echo "$WS2  :: $out2"
      done
    done
  done
done
echo DONE
