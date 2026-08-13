#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166; H="$SHARED_APP_HOST"
echo "=== FULL body of the 400 over HTTPS (names the exact problem) ==="
kubectl -n "$NS" run b-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sS --resolve $H:443:$LB -w '\nHTTP=%{http_code}\n' -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'client_id=admin-cli' --data-urlencode 'username=admin' --data-urlencode 'password=admin' --data-urlencode 'grant_type=password' https://$H/keycloak/realms/master/protocol/openid-connect/token" 2>&1 | grep -avi memcache | tail -6
echo "=== and the SAME request via kcadm-proven localhost (control) — body ==="
KCPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^keycloak-[0-9a-f]' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$KCPOD" -- sh -lc 'command -v curl >/dev/null 2>&1 && curl -sS -H "Content-Type: application/x-www-form-urlencoded" --data-urlencode client_id=admin-cli --data-urlencode username=admin --data-urlencode password=admin --data-urlencode grant_type=password http://localhost:8080/keycloak/realms/master/protocol/openid-connect/token; echo; echo "(no curl in kc pod if blank)"' 2>&1 | grep -avi memcache | tail -4
echo DONE
