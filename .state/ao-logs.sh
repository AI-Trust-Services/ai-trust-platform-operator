cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/ao-logs.out 2>&1

echo "===== ACCOUNT-OPERATOR LOGS (CA/issuer/oidc/keycloak/authconfig) ====="
kubectl -n platform-mesh-system logs deploy/account-operator --since=48h 2>&1 | grep -avi memcache | grep -iE 'authenticationconfig|certificateauthorit|issuer|oidc|keycloak|trust|\bca\b|pem|certificate' | tail -80

echo
echo "===== ACCOUNT-OPERATOR LOG SAMPLE (last 60 lines any) ====="
kubectl -n platform-mesh-system logs deploy/account-operator --since=48h --tail=60 2>&1 | grep -avi memcache
