cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp

echo "===== 1. curl pod: GET luigi-config.js headers ====="
kubectl -n "$NS" run cache-check-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --command -- \
  curl -sS -D - -o /dev/null "http://shell.aitrust-mt-msp.svc.cluster.local:80/luigi-config.js" 2>&1 | grep -avi memcache

echo ""
echo "===== 2. find shell pod ====="
SHELL_POD=$(kubectl -n "$NS" get pods -l app=shell -o name 2>/dev/null | head -1 | grep -avi memcache)
if [ -z "$SHELL_POD" ]; then
  echo "no app=shell label, listing pods:"
  kubectl -n "$NS" get pods 2>&1 | grep -avi memcache
fi
echo "SHELL_POD=$SHELL_POD"
