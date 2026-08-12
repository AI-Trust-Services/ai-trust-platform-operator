#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step2-checkpoint.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "############ CHECKPOINT — is platform auth healthy after the CA-bundle change? ############"
echo "-- 1. served cert is STILL self-signed (we have NOT swapped yet) --"
kubectl -n "$GWNS" get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -subject 2>&1 | grep -avi memcache

echo "-- 2. all WACs carry 5 certs (bundle applied everywhere) --"
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
echo -n "  root/orgs-authentication: "; kc root get workspaceauthenticationconfiguration orgs-authentication -o jsonpath='{.spec.jwt[0].issuer.certificateAuthority}' 2>/dev/null | grep -c 'BEGIN CERT'
for n in aitrustdemo demo aitrustg2 poc; do
  echo -n "  root:orgs/$n: "; kc root:orgs get workspaceauthenticationconfiguration "$n" -o jsonpath='{.spec.jwt[0].issuer.certificateAuthority}' 2>/dev/null | grep -c 'BEGIN CERT'
done

echo "-- 3. frontproxy + root-kcp shard + iam: any x509 / tokenreview / oidc errors in last 2 min? (expect NONE) --"
FP=$(kubectl -n "$GWNS" get deploy -o name 2>/dev/null | grep -avi memcache | grep -iE 'front-proxy' | head -1)
kubectl -n "$GWNS" logs "$FP" --since=3m 2>&1 | grep -avi memcache | grep -iE 'x509|unknown authority|tokenreview|oidc' | tail -6 || true
SH=$(kubectl -n "$GWNS" get pods -o name 2>/dev/null | grep -avi memcache | grep -iE 'root-kcp' | head -1)
echo "  shard: $SH"
kubectl -n "$GWNS" logs "$SH" --since=3m 2>&1 | grep -avi memcache | grep -iE 'x509|unknown authority|oidc|authentication error' | tail -6 || true
kubectl -n "$GWNS" logs deploy/iam-service --since=3m 2>&1 | grep -avi memcache | grep -iE 'x509|tls|error' | tail -6 || true
echo "  (empty above = no auth errors)"

echo "-- 4. THE functional test: can we LIST org units via the platform (root:orgs)? --"
echo -n "  root:orgs workspaces reachable: "
kc root:orgs get workspace --no-headers 2>&1 | grep -avi memcache | wc -l
kc root:orgs get workspace 2>&1 | grep -avi memcache | head

echo "-- 5. instances still Ready (auth plane didn't disturb them) --"
kubectl get aitrustplatforminstances.trust.aitrust.msp -A 2>&1 | grep -avi memcache
echo CHECKPOINT_DONE
