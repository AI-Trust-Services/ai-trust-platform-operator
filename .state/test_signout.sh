#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

PROXY=http://oauth2-proxy-fridaytest.aitrust-mt-msp.svc.cluster.local:8080
SUFFIX=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
ORIGIN=https://ai-trust-mt-fridaytest.$SUFFIX
KCLOGOUT="https://$SUFFIX/keycloak/realms/fridaytest/protocol/openid-connect/logout?post_logout_redirect_uri=$ORIGIN&client_id=aitrust-mt-app"

# URL-encode the rd value the way the shell does
INNER='RD=$(printf "%s" "$KCLOGOUT" | sed "s/:/%3A/g; s#/#%2F#g; s/?/%3F/g; s/=/%3D/g; s/&/%26/g")
echo "=== GET /oauth2/sign_out?rd=<keycloak-logout> (no session) — what does the proxy return? ==="
curl -s -o /dev/null -w "HTTP %{http_code} -> %{redirect_url}\n" "$PROXY/oauth2/sign_out?rd=$RD"
echo "=== GET /oauth2/sign_out (plain, no rd) ==="
curl -s -o /dev/null -w "HTTP %{http_code} -> %{redirect_url}\n" "$PROXY/oauth2/sign_out"'
kubectl -n "$NS" run signouttest-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet \
  --env="PROXY=$PROXY" --env="KCLOGOUT=$KCLOGOUT" --command -- sh -c "$INNER" 2>&1 | f

echo; echo "=== current fridaytest proxy args (full) ==="
kubectl -n "$NS" get deploy oauth2-proxy-fridaytest -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f
echo DONE
