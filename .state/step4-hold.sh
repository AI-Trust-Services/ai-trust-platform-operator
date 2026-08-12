#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step4-hold.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
LB=130.214.18.166; GWNS=platform-mesh-system

echo "############ HOLD THROUGH FLUX RECONCILE (~2.5 min) — did anything revert the served cert or WACs? ############"
echo "== t0 =="
kubectl -n "$GWNS" get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer 2>&1 | grep -avi memcache
sleep 150
echo "== t+150s: served cert issuer (must still be Let's Encrypt) =="
kubectl -n "$GWNS" get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer -subject 2>&1 | grep -avi memcache
echo "== t+150s: served per-SNI (apex + testai) =="
for H in "$SUF" "testai.$SUF"; do
  kubectl -n "$GWNS" run h-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
    sh -c "curl -sS --resolve $H:443:$LB https://$H/ -o /dev/null -w '$H http=%{http_code} tls_ok\n' 2>&1" 2>&1 | grep -avi memcache | grep -E 'http=|SSL'
done
echo "== t+150s: WAC still has 5-cert bundle (not reverted by account-operator)? =="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
echo -n "  root/orgs-authentication certs: "; kc root get workspaceauthenticationconfiguration orgs-authentication -o jsonpath='{.spec.jwt[0].issuer.certificateAuthority}' 2>/dev/null | grep -c 'BEGIN CERT'
echo -n "  root:orgs reachable: "; kc root:orgs get workspace --no-headers 2>&1 | grep -avi memcache | grep -c Ready
echo HOLD_DONE
