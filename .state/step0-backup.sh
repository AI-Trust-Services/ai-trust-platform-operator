#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step0-backup.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
rm -f "$SHOOT_KUBECONFIG"; mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
export KUBECONFIG="$SHOOT_KUBECONFIG"
GWNS=platform-mesh-system
BK=.state/backup-dnscert2
mkdir -p "$BK"

echo "############ snapshot secrets (served cert + pinned CA) ############"
kubectl -n "$GWNS" get secret domain-certificate    -o yaml 2>&1 | grep -avi memcache > "$BK/domain-certificate.yaml"; echo "  domain-certificate.yaml  $(wc -l < "$BK/domain-certificate.yaml") lines"
kubectl -n "$GWNS" get secret domain-certificate-ca -o yaml 2>&1 | grep -avi memcache > "$BK/domain-certificate-ca.yaml"; echo "  domain-certificate-ca.yaml  $(wc -l < "$BK/domain-certificate-ca.yaml") lines"
kubectl -n "$GWNS" get secret cert-aitrust-full     -o yaml 2>&1 | grep -avi memcache > "$BK/cert-aitrust-full.yaml"; echo "  cert-aitrust-full.yaml  $(wc -l < "$BK/cert-aitrust-full.yaml") lines"

echo "############ snapshot gateway + iam-service deploy ############"
kubectl -n "$GWNS" get gateway k8sapi-gateway -o yaml 2>&1 | grep -avi memcache > "$BK/gateway.yaml"; echo "  gateway.yaml  $(wc -l < "$BK/gateway.yaml") lines"
kubectl -n "$GWNS" get deploy iam-service -o yaml 2>&1 | grep -avi memcache > "$BK/iam-service.yaml"; echo "  iam-service.yaml  $(wc -l < "$BK/iam-service.yaml") lines"

echo "############ snapshot ALL WorkspaceAuthenticationConfiguration CRs (root + each org) ############"
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
# root workspace WACs
kc root get workspaceauthenticationconfiguration -o yaml 2>&1 | grep -avi memcache > "$BK/wac-root.yaml"
echo "  wac-root.yaml  $(wc -l < "$BK/wac-root.yaml") lines"
kc root get workspaceauthenticationconfiguration 2>&1 | grep -avi memcache
# root:orgs WACs (one per org)
kc root:orgs get workspaceauthenticationconfiguration -o yaml 2>&1 | grep -avi memcache > "$BK/wac-orgs.yaml"
echo "  wac-orgs.yaml  $(wc -l < "$BK/wac-orgs.yaml") lines"
echo "-- WAC names in root:orgs --"
kc root:orgs get workspaceauthenticationconfiguration -o custom-columns='NAME:.metadata.name' 2>&1 | grep -avi memcache

echo "############ verify current served cert = self-signed (baseline) ############"
kubectl -n "$GWNS" get secret domain-certificate -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -issuer -subject 2>&1 | grep -avi memcache

echo "############ ROLLBACK DRY-RUN (prove the revert command is valid, do NOT apply) ############"
kubectl create secret tls domain-certificate --cert=prerequisites/tls.crt --key=prerequisites/tls.key \
  --dry-run=client -o yaml 2>&1 | grep -avi memcache | grep -E 'kind:|name:|tls.crt' | head
echo "BACKUP_DONE"
