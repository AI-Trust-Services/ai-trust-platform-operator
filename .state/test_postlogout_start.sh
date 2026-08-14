#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
KC=http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak
ORIGIN=https://ai-trust-mt-fridaytest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
# Does KC accept post_logout_redirect_uri = origin/oauth2/start ? (covered by registered origin/* )
INNER='echo "-- KC logout with post_logout_redirect_uri = ORIGIN/oauth2/start --"
curl -s -o /dev/null -w "HTTP %{http_code} -> %{redirect_url}\n" "$KC/realms/fridaytest/protocol/openid-connect/logout?post_logout_redirect_uri=$ORIGIN/oauth2/start&client_id=aitrust-mt-app"'
kubectl -n "$NS" run plstart-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet \
  --env="KC=$KC" --env="ORIGIN=$ORIGIN" --command -- sh -c "$INNER" 2>&1 | f
echo DONE
