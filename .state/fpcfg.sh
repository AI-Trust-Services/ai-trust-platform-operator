#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/fpcfg.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "############ frontproxy-config CM — the authentication config (OIDC issuer + CA trust) ############"
kubectl -n "$GWNS" get cm frontproxy-config -o jsonpath='{range .data}{@}{"\n"}{end}' 2>/dev/null | grep -avi memcache
echo "---- (raw keys) ----"
kubectl -n "$GWNS" get cm frontproxy-config -o jsonpath='{.data}' 2>&1 | grep -avi memcache | tr ',' '\n' | head -40

echo
echo "############ full data dump of frontproxy-config ############"
kubectl -n "$GWNS" get cm frontproxy-config -o yaml 2>&1 | grep -avi memcache | sed -n '1,160p'

echo
echo "############ does the OIDC config point at the apex host + a CA file? grep the rendered config ############"
kubectl -n "$GWNS" get cm frontproxy-config -o yaml 2>&1 | grep -avi memcache | grep -iE 'issuer|oidc|certificateAuthority|ca-file|caFile|ai-trust-1|keycloak|realms|\.well-known'
echo DONE
