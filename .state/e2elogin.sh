#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
H=ai-trust-mt-poc2.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== per-org host /oauth2/start → expect 302 to poc2 realm auth ==="
kubectl -n "$NS" run e2e-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -H 'Accept: text/html' -o /dev/null -w 'start: http=%{http_code}\n  loc=%{redirect_url}\n' --resolve $H:443:$LB 'https://$H/oauth2/start?rd=%2F'" 2>&1 | grep -avi memcache | grep -E 'http=|loc='
echo "=== root / (should reach oauth2-proxy, 403/302 not 404) ==="
kubectl -n "$NS" run e2e2-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w 'root: http=%{http_code}\n' --resolve $H:443:$LB https://$H/" 2>&1 | grep -avi memcache | grep http=
echo "=== oauth2-proxy-poc2 pod: any redeem/config errors? ==="
kubectl -n "$NS" logs deploy/oauth2-proxy-poc2 --tail=10 2>&1 | grep -avi memcache | grep -viE 'GET /ping' | tail -6
echo DONE
