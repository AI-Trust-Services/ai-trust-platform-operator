#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
SHARED=ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== roll operator to v4 (tenant URL = shared app host) ==="
kubectl -n "$NS" set image deploy/aitrust-mt-operator '*'=mirceacraciun795/aitrust-mt-operator:v4 2>&1 | grep -avi memcache
kubectl -n "$NS" rollout status deploy/aitrust-mt-operator --timeout=120s 2>&1 | grep -avi memcache | tail -1
# force a reconcile by nudging the CRs (annotate) so status.url updates now
sleep 25
echo "=== Subscriptions now (url should be the SHARED host) ==="
kubectl get subscriptions.sub.aitrustmt.msp -A -o custom-columns='NAME:.metadata.name,READY:.status.ready,PHASE:.status.phase,URL:.status.url' 2>&1 | grep -avi memcache
echo "=== the SHARED app host actually serves the AI Trust app (not the portal)? ==="
echo "-- what does the shared host return + is it the app (oauth gate) vs portal? --"
kubectl -n "$NS" run s-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk --resolve $SHARED:443:$LB https://$SHARED/ -w '\nHTTP=%{http_code}\n' | grep -oiE 'luigi-core|ai.trust|oauth2|sign_in|<title>[^<]*</title>' | head -5; echo ---" 2>&1 | grep -avi memcache | tail -8
echo "=== CONFIRM the routing hijack: does the per-tenant host hit the mesh PORTAL (luigi-core)? ==="
H=38ef9l9wvvoacrsm-pocmt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
kubectl -n "$NS" run t-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk --resolve $H:443:$LB https://$H/ | grep -oiE 'luigi-core|ai.trust|<title>[^<]*</title>' | head -3" 2>&1 | grep -avi memcache | tail -4
echo DONE
