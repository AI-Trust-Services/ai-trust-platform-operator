#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
# Simulate a top-level document navigation (no cookie) to the tenant root THROUGH the proxy service.
# Expect: 302 -> Keycloak login (that's correct logged-out behavior). A 403 on the document would be the bug.
INNER='echo "-- GET / (document nav, no cookie) --"
curl -s -o /dev/null -w "root: HTTP %{http_code}  ->  %{redirect_url}\n" -H "Accept: text/html" http://oauth2-proxy-fridaytest.aitrust-mt-msp.svc.cluster.local:8080/
echo "-- GET /overview/ (document nav) --"
curl -s -o /dev/null -w "overview: HTTP %{http_code}  ->  %{redirect_url}\n" -H "Accept: text/html" http://oauth2-proxy-fridaytest.aitrust-mt-msp.svc.cluster.local:8080/overview/'
kubectl -n "$NS" run navtest-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- sh -c "$INNER" 2>&1 | f
