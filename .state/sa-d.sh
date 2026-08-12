#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/sa-d.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
PNS="${PROVIDER_NS:-aitrust-msp}"

echo "=== the shoot-mirror d object: its annotations/labels reveal the UPSTREAM kcp cluster + namespace ==="
kubectl -n 33hins0iklcwfg45 get aitrustplatforminstances.trust.aitrust.msp d -o json 2>/dev/null \
  | grep -av memcache \
  | python3 -c 'import sys,json; o=json.load(sys.stdin); m=o["metadata"]; print("ANNOTATIONS:"); [print("  ",k,"=",v) for k,v in (m.get("annotations") or {}).items()]; print("LABELS:"); [print("  ",k,"=",v) for k,v in (m.get("labels") or {}).items()]' 2>&1 | grep -av memcache

echo
echo "=== syncagent logs mentioning d (shows upstream path it syncs FROM) ==="
kubectl -n "$PNS" logs deploy/aitrust-msp-operator -c '*' --tail=1 >/dev/null 2>&1
SA=$(kubectl -n "$PNS" get deploy -o name 2>/dev/null | grep -av memcache | grep -iE 'syncagent|agent' | head -1)
echo "syncagent deploy: $SA"
kubectl -n "$PNS" logs "$SA" --tail=80 2>&1 | grep -av memcache | grep -iE '"d"|/d |cluster|workspace|orgs' | tail -20
echo DONE
