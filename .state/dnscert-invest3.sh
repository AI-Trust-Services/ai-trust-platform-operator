#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/dnscert-invest3.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
LB=130.214.18.166; GWNS=platform-mesh-system

echo "############ A. FULL-SAN of the LE cert cert-aitrust-full (must cover apex + *.ai-trust-1 + *.services) ############"
kubectl -n "$GWNS" get secret cert-aitrust-full -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/full.crt
echo "-- issuer/subject/enddate --"; openssl x509 -in /tmp/full.crt -noout -issuer -subject -enddate 2>&1 | grep -avi memcache
echo "-- SAN list --"; openssl x509 -in /tmp/full.crt -noout -text 2>/dev/null | grep -A3 'Subject Alternative Name' | grep -avi memcache

echo
echo "############ B. cert-p1 + cert-p2 SANs (fallback options) ############"
for S in cert-p1 cert-p2; do
  echo "-- $S --"
  kubectl -n "$GWNS" get secret "$S" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/$S.crt
  openssl x509 -in /tmp/$S.crt -noout -subject 2>&1 | grep -avi memcache
  openssl x509 -in /tmp/$S.crt -noout -text 2>/dev/null | grep -A2 'Subject Alternative Name' | tail -1 | grep -avi memcache
done

echo
echo "############ C. FRONTPROXY AUTH HEALTH — is org auth working RIGHT NOW? ############"
echo "-- last 300 log lines, any x509/oidc/tokenreview/401 (empty = healthy) --"
kubectl -n "$GWNS" logs deploy/frontproxy-front-proxy --tail=300 2>&1 | grep -avi memcache | grep -iE 'x509|unknown authority|tokenreview|oidc|401|authenticator' | tail -12
echo "  (if empty above => no auth errors => healthy)"

echo
echo "############ D. FRONTPROXY OIDC TRUST CONFIG — how does it trust Keycloak's cert? (THE crux) ############"
echo "-- deploy args/env mentioning oidc/ca/issuer --"
kubectl -n "$GWNS" get deploy frontproxy-front-proxy -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{": args="}{.args}{" "}{.command}{"\n"}{end}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'oidc|ca-file|ca-bundle|issuer|authentication-config|client-ca'
echo "-- volumes/secrets mounted (look for a CA bundle) --"
kubectl -n "$GWNS" get deploy frontproxy-front-proxy -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{" -> secret="}{.secret.secretName}{" cm="}{.configMap.name}{"\n"}{end}' 2>&1 | grep -avi memcache
echo "-- any authentication config file referenced? --"
kubectl -n "$GWNS" get cm 2>&1 | grep -avi memcache | grep -iE 'front|oidc|auth' | head

echo
echo "############ E. served cert per-SNI (using curl image with openssl available) ############"
for H in "$SUF" "testai.$SUF"; do
  echo "--- $H ---"
  kubectl -n "$GWNS" run c-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
    curl -sv --resolve "$H:443:$LB" "https://$H/" -o /dev/null 2>&1 | grep -avi memcache | grep -iE 'issuer:|subject:|SSL certificate verify'
done
echo DONE
