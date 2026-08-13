#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
H=ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== browser-like GET / (Accept html) — expect 302 to mesh poc2 login ==="
kubectl -n "$NS" run b-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -H 'Accept: text/html' -o /dev/null -w 'GET /: http=%{http_code}\n  location=%{redirect_url}\n' --resolve $H:443:$LB https://$H/" 2>&1 | grep -avi memcache | grep -E 'http=|location='
echo "=== hit /oauth2/start directly (oauth2-proxy's own login initiator) — expect 302 to keycloak poc2 ==="
kubectl -n "$NS" run s-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -H 'Accept: text/html' -o /dev/null -w 'GET /oauth2/start: http=%{http_code}\n  location=%{redirect_url}\n' --resolve $H:443:$LB 'https://$H/oauth2/start?rd=%2F'" 2>&1 | grep -avi memcache | grep -E 'http=|location='
echo DONE
