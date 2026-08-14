cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
POD=shell-8b59c59f9-cftdj

echo "===== nginx.conf ====="
kubectl -n "$NS" exec "$POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -avi memcache

echo ""
echo "===== conf.d listing ====="
kubectl -n "$NS" exec "$POD" -- ls -la /etc/nginx/conf.d/ 2>&1 | grep -avi memcache

echo ""
echo "===== conf.d contents ====="
for f in $(kubectl -n "$NS" exec "$POD" -- sh -c 'ls /etc/nginx/conf.d/' 2>/dev/null); do
  echo "----- /etc/nginx/conf.d/$f -----"
  kubectl -n "$NS" exec "$POD" -- cat "/etc/nginx/conf.d/$f" 2>&1 | grep -avi memcache
done

echo ""
echo "===== grep expires / cache-control across nginx dirs ====="
kubectl -n "$NS" exec "$POD" -- sh -c 'grep -rniE "expires|cache-control|add_header|location" /etc/nginx/ 2>/dev/null' 2>&1 | grep -avi memcache
