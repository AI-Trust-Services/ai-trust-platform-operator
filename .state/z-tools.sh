cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh
load_config
export KUBECONFIG=""
echo "=== does oauth2-proxy pod have wget/curl? ==="
kubectl -n ai-trust-app exec deploy/oauth2-proxy -- sh -c "which wget curl 2>/dev/null; echo rc=0" 2>&1 | grep -avi memcache
echo "=== does shell pod have wget/curl? ==="
kubectl -n ai-trust-app exec deploy/shell -- sh -c "which wget curl 2>/dev/null; echo rc=0" 2>&1 | grep -avi memcache
