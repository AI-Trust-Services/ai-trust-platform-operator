cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/infra-hr.out 2>&1

echo "===== HELMRELEASES in platform-mesh-system ====="
kubectl -n platform-mesh-system get helmrelease 2>&1 | grep -avi memcache

echo
echo "===== INFRA HELMRELEASE (full) ====="
kubectl -n platform-mesh-system get helmrelease infra -o yaml 2>&1 | grep -avi memcache
