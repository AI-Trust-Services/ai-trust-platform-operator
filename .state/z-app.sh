cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""
echo "=== ai-trust-app pods ==="
kubectl -n ai-trust-app get pods -o wide 2>&1 | grep -avi memcache
echo "=== ai-trust-app services ==="
kubectl -n ai-trust-app get svc 2>&1 | grep -avi memcache
echo "=== HTTPRoutes all ns ==="
kubectl get httproute -A 2>&1 | grep -avi memcache
