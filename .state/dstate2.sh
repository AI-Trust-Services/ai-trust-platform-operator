#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== authoritative: ALL namespaces starting aitp (fresh token) ==="
kubectl get ns 2>&1 | grep -avi memcache | grep aitp || echo "  NONE"
echo "=== d's expected namespace (from CR status.url host 25veqwflh7syq7fm-d) ==="
kubectl get ns aitp-25veqwflh7syq7fm-d 2>&1 | grep -avi memcache
echo "=== if present, are its pods up? ==="
kubectl -n aitp-25veqwflh7syq7fm-d get deploy oauth2-proxy shell 2>&1 | grep -avi memcache | head
echo "=== consumer CR d status again (Ready + which ns does it claim?) ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
kc root:orgs:aitrustg2:demo -n default get aitrustplatforminstance d -o jsonpath='phase={.status.phase} ready={.status.ready} ns={.status.namespace} url={.status.url}{"\n"}' 2>&1 | grep -avi memcache
echo "=== external reach of d (the surviving instance) ==="
LB=130.214.18.166; H=25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
kubectl -n platform-mesh-system run rd-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w "d ext / : http=%{http_code} time=%{time_total}s\n" --resolve "$H:443:$LB" "https://$H/" 2>&1 | grep -avi memcache | grep http=
