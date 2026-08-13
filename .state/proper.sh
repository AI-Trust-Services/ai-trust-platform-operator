#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166; H="$SHARED_APP_HOST"
echo "=== proper token POST over HTTPS (explicit content-type) — expect 200 ==="
kubectl -n "$NS" run hp-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sS --resolve $H:443:$LB -o /dev/null -w 'https token (proper): http=%{http_code}\n' -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'client_id=admin-cli' --data-urlencode 'username=admin' --data-urlencode 'password=admin' --data-urlencode 'grant_type=password' https://$H/keycloak/realms/master/protocol/openid-connect/token" 2>&1 | grep -avi memcache | grep http=
echo DONE
