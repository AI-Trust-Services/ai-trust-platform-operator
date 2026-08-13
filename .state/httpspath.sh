#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166; H="$SHARED_APP_HOST"
echo "=== is the master token endpoint reachable+trusted over the PUBLIC HTTPS gateway (LE cert)? ==="
echo "   (no -k = verifies against public trust store; expect 200 if admin ok + not oauth-gated)"
kubectl -n "$NS" run h-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sS --resolve $H:443:$LB -o /dev/null -w 'https master token: http=%{http_code}\n' -d 'client_id=admin-cli&username=admin&password=admin&grant_type=password' https://$H/keycloak/realms/master/protocol/openid-connect/token 2>&1" 2>&1 | grep -avi memcache | grep -E 'http=|SSL|curl'
echo
echo "=== is /keycloak oauth-gated? check what a plain GET of the master realm returns over HTTPS ==="
kubectl -n "$NS" run hg-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sS --resolve $H:443:$LB -o /dev/null -w 'GET /keycloak/realms/master: http=%{http_code} -> %{redirect_url}\n' https://$H/keycloak/realms/master 2>&1" 2>&1 | grep -avi memcache | grep -E 'http='
echo
echo "=== does shell nginx proxy /keycloak → keycloak? (the path that makes HTTPS work w/o oauth gate) ==="
SHPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^shell-' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$SHPOD" -- sh -c 'grep -A2 "location /keycloak" /etc/nginx/nginx.conf 2>/dev/null || grep -rA2 keycloak /etc/nginx/ 2>/dev/null | head' 2>&1 | grep -avi memcache | head
echo DONE
