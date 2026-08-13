cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""
echo "=== running oauth2-proxy FULL args (looking for skip-auth / api-route / set-authorization) ==="
kubectl -n ai-trust-app get deploy oauth2-proxy -o jsonpath="{.spec.template.spec.containers[0].args}" 2>&1 | grep -avi memcache | tr "," "\n"
echo ""
echo "=== template 40 oauth2-proxy: any skip-auth-route? ==="
grep -nE "skip-auth|api-route|set-authorization|pass-authorization|skip-jwt" config/k8s-app/40-workers-shell-proxy.yaml
