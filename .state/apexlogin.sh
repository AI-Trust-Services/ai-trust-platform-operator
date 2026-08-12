#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
A=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== apex / : does it redirect to a login (302) or 401 immediately? (browser-like) ==="
kubectl -n platform-mesh-system run a1-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'apex / : http=%{http_code} -> %{redirect_url}\n' -H 'Accept: text/html' --resolve "$A:443:$LB" "https://$A/" 2>&1 | grep -av memcache | grep -E 'http=|SSL'
echo "=== the portal auth endpoint the SPA calls (where the 401 came from is an API call, not the login) ==="
echo "    the 401 on /gateway/.../graphql is EXPECTED when the SPA has no token yet; the fix is completing the /welcome login."
echo "=== confirm welcome realm has a usable login (clients + a user)? ==="
kubectl -n platform-mesh-system exec keycloak-0 -- sh -c '/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1 && echo REALMS: && /opt/keycloak/bin/kcadm.sh get realms --fields realm 2>/dev/null | tr -d "  \n" && echo && echo WELCOME_USERS: && /opt/keycloak/bin/kcadm.sh get users -r welcome --fields username 2>/dev/null' 2>&1 | grep -av memcache | head -20
