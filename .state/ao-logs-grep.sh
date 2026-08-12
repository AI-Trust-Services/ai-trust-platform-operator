cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/ao-logs-grep.out 2>&1

echo "===== log lines mentioning CA source / secret / configmap / read ====="
kubectl -n platform-mesh-system logs deploy/account-operator --since=48h 2>&1 | grep -avi memcache | grep -iE 'certificateauthorit|domain-certificate|caSecret|configmap|secret|read.*ca|trust|welcome|realms' | tail -60
echo
echo "===== log lines around poc workspace creation ====="
kubectl -n platform-mesh-system logs deploy/account-operator --since=1h 2>&1 | grep -avi memcache | grep -iE 'poc' | tail -40
