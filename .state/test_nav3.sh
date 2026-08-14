#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
INNER='echo "-- GET / (document nav, no cookie) — expect 302 to keycloak now --"
curl -s -o /dev/null -w "root: HTTP %{http_code} -> %{redirect_url}\n" -H "Accept: text/html,application/xhtml+xml" http://oauth2-proxy-fridaytest.aitrust-mt-msp.svc.cluster.local:8080/'
kubectl -n "$NS" run nav3-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- sh -c "$INNER" 2>&1 | f
