#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
INNER='echo "-- GET / with full browser Accept header --"
curl -s -D - -o /dev/null -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" http://oauth2-proxy-fridaytest.aitrust-mt-msp.svc.cluster.local:8080/ | head -15
echo "-- GET /oauth2/start (the login initiator) --"
curl -s -o /dev/null -w "oauth2/start: HTTP %{http_code} -> %{redirect_url}\n" http://oauth2-proxy-fridaytest.aitrust-mt-msp.svc.cluster.local:8080/oauth2/start'
kubectl -n "$NS" run nav2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- sh -c "$INNER" 2>&1 | f
echo; echo "-- current proxy args (skip-provider-button? whitelist? --) --"
kubectl -n "$NS" get deploy oauth2-proxy-fridaytest -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f | grep -iE 'skip|provider-button|reverse|redirect|whitelist|banner|footer|silent'
