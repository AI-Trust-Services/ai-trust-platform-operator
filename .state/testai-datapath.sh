#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitp-33hins0iklcwfg45-testai
echo "=== give oauth2-proxy a moment, confirm it stays Running + all instance deploys 1/1 ==="
sleep 10
kubectl -n "$NS" get pods 2>&1 | grep -av memcache | grep -vE '1/1 .*Running|Completed' ; echo "(only not-ready above; empty = all good)"
echo "=== the alerts API served by alerts-backend directly (is the DATA path alive)? ==="
kubectl -n "$NS" run a-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- sh -c '
echo -n "alerts-backend /health: "; curl -sS -o /dev/null -w "%{http_code}\n" http://alerts-backend:8005/health;
echo -n "alerts-backend a real API (v1/alerts): "; curl -sS -o /dev/null -w "%{http_code}\n" http://alerts-backend:8005/v1/alerts 2>/dev/null;
echo -n "monitoring-backend /health: "; curl -sS -o /dev/null -w "%{http_code}\n" http://monitoring-backend:8003/health 2>/dev/null;
' 2>&1 | grep -av memcache
echo "=== how does the shell route /api/alerts? nginx.conf peek (is the 504 a shell-route or backend issue?) ==="
POD=$(kubectl -n "$NS" get pods -o name 2>/dev/null | grep -av memcache | grep shell | head -1)
kubectl -n "$NS" exec "$POD" -- sh -c 'grep -iE "alerts|api|proxy_pass|location" /etc/nginx/nginx.conf 2>/dev/null | head -20' 2>&1 | grep -av memcache | head -20
