#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitp-33hins0iklcwfg45-testai
echo "=== testai pods: all Running? ==="
kubectl -n "$NS" get pods 2>&1 | grep -av memcache | grep -vE 'Running|Completed' ; echo "(only NOT-running shown; empty=all good)"
kubectl -n "$NS" get deploy 2>&1 | grep -av memcache | awk 'NR==1||$2!~/^([0-9]+)\/\1$/{if(NR>1 && $2!=$3"/"$3){}} {print}' | awk '$2!="1/1"&&NR>1{print "NOTREADY",$1,$2}'; echo "(deploys not 1/1 above)"
echo "=== the app is served via oauth2-proxy -> shell; is shell + the alerts MFE up? ==="
kubectl -n "$NS" get deploy alerts-frontend alerts-backend shell oauth2-proxy 2>&1 | grep -av memcache
echo "=== fetch the alerts MFE + its API through the instance (in-cluster, past oauth) — do they 200? ==="
kubectl -n "$NS" run t-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- sh -c '
echo -n "alerts-frontend: "; curl -sS -o /dev/null -w "%{http_code}\n" http://alerts-frontend:80/ ;
echo -n "alerts-backend health: "; curl -sS -o /dev/null -w "%{http_code}\n" http://alerts-backend:8005/health 2>/dev/null || echo "no /health";
echo -n "shell: "; curl -sS -o /dev/null -w "%{http_code}\n" http://shell:80/ ;
' 2>&1 | grep -av memcache
