#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
H=38ef9l9wvvoacrsm-pocmt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== pocmt CR annotations (is kcp.io/path present → correct org realm?) ==="
kubectl -n 38ef9l9wvvoacrsm get subscriptions.sub.aitrustmt.msp pocmt -o jsonpath='{.metadata.annotations}{"\n"}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'kcp.io/path|remote-object|cluster' | head
echo "=== is pocmt's host reachable via the shared app? (403 = healthy oauth gate) ==="
kubectl -n "$NS" run r-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w 'pocmt https://host/: http=%{http_code}\n' --resolve $H:443:$LB https://$H/" 2>&1 | grep -avi memcache | grep http=
echo "=== is there an HTTPRoute for the pocmt host? (per-tenant subdomain → shared app) ==="
kubectl -n platform-mesh-system get httproute 2>&1 | grep -avi memcache | grep -iE 'pocmt|38ef9|aitrust-mt-shared|NAME' | head
echo DONE
