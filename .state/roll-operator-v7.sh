#!/bin/bash
# Roll the operator to v7 (embeds shell imagePullPolicy:Always) so every FUTURE Enable pulls the fixed shell.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS="${PROVIDER_NS:-aitrust-msp}"
echo "=== operator deploy name ==="
DEP=$(kubectl -n "$NS" get deploy -o name 2>&1 | grep -av memcache | grep -iE 'operator' | head -1)
echo "  $DEP"
echo "=== set image to v7 + roll ==="
kubectl -n "$NS" set image "$DEP" '*'=mirceacraciun795/aitrust-msp-operator:v7 2>&1 | grep -av memcache
kubectl -n "$NS" rollout status "$DEP" --timeout=120s 2>&1 | grep -av memcache | tail -1
echo "=== confirm running image ==="
kubectl -n "$NS" get "$DEP" -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | grep -av memcache
