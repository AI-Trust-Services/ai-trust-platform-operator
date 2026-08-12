#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
H=testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== what cert does testai serve NOW (after rollback)? ==="
kubectl -n platform-mesh-system run c-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -ksv --resolve "$H:443:$LB" "https://$H/" 2>&1 | grep -av memcache | grep -iE 'issuer:|subject:' | head -2
echo "=== does the app root + a typical MFE/API path respond through the gateway (browser path)? ==="
for p in / /alerts/ /api/alerts/v1/ ; do
  kubectl -n platform-mesh-system run p-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
    curl -sk -o /dev/null -w "$p -> http=%{http_code}\n" --resolve "$H:443:$LB" "https://$H$p" 2>&1 | grep -av memcache | grep 'http='
done
echo "=== is oauth2-proxy for testai settled again (it was ContainerCreating)? ==="
kubectl -n aitp-33hins0iklcwfg45-testai get pods 2>&1 | grep -av memcache | grep oauth2-proxy
echo "=== the shell serves the app HTML; does its luigi config reference the right host? peek ==="
kubectl -n aitp-33hins0iklcwfg45-testai run s-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS http://shell:80/ 2>&1 | grep -av memcache | grep -oiE 'luigi-config[^"]*|/assets/[^"]*|apiUrl[^,]*' | head -5
