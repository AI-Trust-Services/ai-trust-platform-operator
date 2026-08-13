cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""
echo "=== shell image ==="
kubectl -n ai-trust-app get deploy shell -o jsonpath="{.spec.template.spec.containers[*].image}" 2>&1 | grep -avi memcache
echo ""
echo "=== shell nginx config location ==="
kubectl -n ai-trust-app exec deploy/shell -- sh -c "ls -la /etc/nginx/ ; echo ---; ls -la /etc/nginx/conf.d/ 2>/dev/null" 2>&1 | grep -avi memcache
