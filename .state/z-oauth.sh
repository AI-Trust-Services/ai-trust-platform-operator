cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""
echo "=== oauth2-proxy args ==="
kubectl -n ai-trust-app get deploy oauth2-proxy -o jsonpath="{.spec.template.spec.containers[0].args}" 2>&1 | grep -avi memcache
echo ""
echo "=== oauth2-proxy env ==="
kubectl -n ai-trust-app get deploy oauth2-proxy -o jsonpath="{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{\"\n\"}{end}" 2>&1 | grep -avi memcache
echo ""
echo "=== keycloak env (KC_*) ==="
kubectl -n ai-trust-app get deploy keycloak -o jsonpath="{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{\"\n\"}{end}" 2>&1 | grep -avi memcache | grep -iE "KC_|HOSTNAME|PROXY|RELATIVE|HTTP"
echo ""
echo "=== keycloak container args/command ==="
kubectl -n ai-trust-app get deploy keycloak -o jsonpath="{.spec.template.spec.containers[0].args}" 2>&1 | grep -avi memcache
