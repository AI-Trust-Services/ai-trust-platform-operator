#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
echo "=== per-org resources for mttest ==="
kubectl -n "$NS" get deploy,svc -l org=mttest --no-headers 2>&1 | grep -avi memcache
kubectl -n "$NS" get job kc-client-mttest --no-headers 2>&1 | grep -avi memcache
kubectl -n "$NS" logs job/kc-client-mttest --tail=3 2>&1 | grep -avi memcache | tail -3
kubectl -n platform-mesh-system get httproute aitrust-mt-mttest --no-headers 2>&1 | grep -avi memcache
echo "=== login flow on the mttest host ==="
H=ai-trust-mt-mttest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
kubectl -n "$NS" run m-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -H 'Accept: text/html' -o /dev/null -w 'start: http=%{http_code}\n  loc=%{redirect_url}\n' --resolve $H:443:$LB 'https://$H/oauth2/start?rd=%2F'" 2>&1 | grep -avi memcache | grep -E 'http=|loc='
echo DONE
