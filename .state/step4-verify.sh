#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step4-verify.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
LB=130.214.18.166; GWNS=platform-mesh-system

echo "############ 1. BROWSER-SIDE: served cert per host is now LE + validates against PUBLIC trust (no -k) ############"
for H in "$SUF" "testai.$SUF" "poc.$SUF" "q3c0weh7suf5hgjk-my-aitrust.$SUF"; do
  echo "--- $H ---"
  kubectl -n "$GWNS" run v-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
    sh -c "curl -sS --resolve $H:443:$LB https://$H/ -o /dev/null -w 'http=%{http_code} tls_verify_ok\n' 2>&1 || echo 'curl-failed (see verify below)'" 2>&1 | grep -avi memcache | grep -E 'http=|curl-failed'
  # show the actual served issuer (with -k so we always see it)
  kubectl -n "$GWNS" run i-$RANDOM --rm -i --restart=Never --image=alpine/openssl --quiet --command -- \
    sh -c "echo | openssl s_client -connect $LB:443 -servername $H 2>/dev/null | openssl x509 -noout -issuer" 2>&1 | grep -avi memcache | grep -i issuer
done

echo
echo "############ 2. does the public trust store accept it? (curl WITHOUT -k must succeed = 200/302/403, not cert error) ############"
kubectl -n "$GWNS" run t-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sS --resolve $SUF:443:$LB https://$SUF/keycloak/realms/master -o /dev/null -w 'apex /keycloak/realms/master (no -k): http=%{http_code}\n' 2>&1" 2>&1 | grep -avi memcache | grep -E 'http=|SSL|certificate'

echo
echo "############ 3. PLATFORM AUTH still healthy? (the last-time breakage) ############"
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
echo -n "  root:orgs workspaces reachable: "; kc root:orgs get workspace --no-headers 2>&1 | grep -avi memcache | grep -c Ready
echo "  -- shard oidc/x509 errors since swap (expect none) --"
SH=$(kubectl -n "$GWNS" get pods -o name 2>/dev/null | grep -avi memcache | grep -iE 'root-kcp' | head -1)
kubectl -n "$GWNS" logs "$SH" --since=4m 2>&1 | grep -avi memcache | grep -iE 'x509|unknown authority|oidc.*error|authentication error|unable to' | tail -8 || true
echo "  (empty = healthy)"

echo
echo "############ 4. instances still Ready ############"
kubectl get aitrustplatforminstances.trust.aitrust.msp -A 2>&1 | grep -avi memcache
echo STEP4_DONE
