#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/oidc-find.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "############ 1. kcp-operator CRs (Kcp/Shard/FrontProxy) — where OIDC/auth is declared ############"
for K in kcps.operator.kcp.io shards.operator.kcp.io frontproxies.operator.kcp.io rootshards.operator.kcp.io; do
  echo "-- $K --"; kubectl -n "$GWNS" get "$K" 2>&1 | grep -avi memcache | head
done

echo
echo "############ 2. grep ALL kcp-operator CRs for oidc/issuer/ca/keycloak/apex ############"
for K in kcps shards frontproxies rootshards; do
  kubectl -n "$GWNS" get "$K.operator.kcp.io" -o yaml 2>/dev/null | grep -avi memcache \
    | grep -iE 'oidc|issuer|clientID|caFile|certificateAuthority|keycloak|realms|ai-trust-1|authentication' && echo "   ^ in $K"
done

echo
echo "############ 3. any CM/secret holding an apiserver authentication-config (oidc) ############"
kubectl -n "$GWNS" get cm,secret 2>&1 | grep -avi memcache | grep -iE 'oidc|auth-config|authentication|structured' | head

echo
echo "############ 4. kcp root shard pod: how is OIDC passed? (args / mounted authentication config) ############"
SH=$(kubectl -n "$GWNS" get pods -o name 2>/dev/null | grep -avi memcache | grep -iE 'root.*shard|kcp.*shard|shard' | head -1)
echo "shard pod: $SH"
[ -n "$SH" ] && kubectl -n "$GWNS" get "$SH" -o jsonpath='{range .spec.containers[*]}{.args}{"\n"}{end}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'oidc|authentication|issuer|client-id|ca-file'

echo
echo "############ 5. who consumes the apex Keycloak over TLS? (the real thing that would break on cert swap) ############"
echo "-- Keycloak service + how it's reached in-cluster --"
kubectl get svc -A 2>&1 | grep -avi memcache | grep -iE 'keycloak' | head
echo "-- iam-service / dex config referencing the apex issuer --"
kubectl -n "$GWNS" get cm,secret 2>&1 | grep -avi memcache | grep -iE 'iam|dex|keycloak' | head
echo DONE
