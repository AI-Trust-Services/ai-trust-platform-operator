#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
echo "=== does the apex use realm 'welcome'? what realms exist in keycloak? ==="
KCP=keycloak-0
kubectl -n platform-mesh-system exec "$KCP" -- bash -c '/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1 && /opt/keycloak/bin/kcadm.sh get realms --fields realm 2>/dev/null' 2>&1 | grep -av memcache | grep -iE 'realm' | head
echo "=== the root:orgs GraphQL — what identity/token does it need? gateway auth mode ==="
kubectl -n platform-mesh-system logs deploy/kubernetes-graphql-gateway --since=15m 2>&1 | grep -av memcache | grep -iE 'root:orgs|401|unauth|token|audience|issuer' | tail -8
echo "=== how does the apex portal expect you to log in? check the 'welcome'/root realm discovery over the new cert ==="
kubectl -n platform-mesh-system run disc-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sS -o /dev/null -w 'welcome realm discovery: http=%{http_code}\n' --resolve ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443:$LB \
  https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak/realms/welcome/.well-known/openid-configuration 2>&1 | grep -av memcache | grep -E 'http=|SSL'
echo "=== does an org I created (aitrustg2) list under root:orgs when properly authed? (via kcp admin) ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 12); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
kc root:orgs get accounts.core.platform-mesh.io 2>&1 | grep -av memcache | head
