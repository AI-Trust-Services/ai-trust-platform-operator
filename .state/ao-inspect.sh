cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/ao-inspect.out 2>&1

echo "===== POD/DEPLOY ENV + ARGS + MOUNTS (account-operator) ====="
kubectl -n platform-mesh-system get deploy account-operator -o yaml 2>&1 | grep -avi memcache

echo
echo "===== ACCOUNT-OPERATOR HELMRELEASE ====="
kubectl -n platform-mesh-system get helmrelease account-operator -o yaml 2>&1 | grep -avi memcache
