cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""
echo "=== nginx.conf ==="
kubectl -n ai-trust-app exec deploy/shell -- cat /etc/nginx/nginx.conf 2>&1 | grep -avi memcache
echo ""
echo "=== conf.d/default.conf ==="
kubectl -n ai-trust-app exec deploy/shell -- cat /etc/nginx/conf.d/default.conf 2>&1 | grep -avi memcache
