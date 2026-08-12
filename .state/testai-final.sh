#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig >/dev/null 2>&1 || { echo LOGIN_EXPIRED; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
H=testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== external app reachability, 3x (expect fast 403 = oauth sign-in, i.e. reachable) ==="
for n in 1 2 3; do
  kubectl -n platform-mesh-system run q-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sk -o /dev/null -w "try$n: http=%{http_code} time=%{time_total}s\n" --resolve "$H:443:$LB" "https://$H/" 2>&1 | grep -av memcache | grep http=
  sleep 3
done
echo "=== the /oauth2/start login redirect (expect 302 -> keycloak = login works) ==="
kubectl -n platform-mesh-system run qs-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w "start: http=%{http_code} -> %{redirect_url}\n" --resolve "$H:443:$LB" "https://$H/oauth2/start" 2>&1 | grep -av memcache | grep http=
echo "=== testai pods still all Running? ==="
kubectl -n aitp-33hins0iklcwfg45-testai get pods --no-headers 2>&1 | grep -av memcache | grep -vE 'Running|Completed' | head; echo "(empty=all good)"
