#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== restart operator so it re-reconciles fresh (RBAC + workloads now all in place) ==="
sk -n aitrust-msp rollout restart deploy/aitrust-msp-operator 2>&1 | grep -av memcache
sk -n aitrust-msp rollout status deploy/aitrust-msp-operator --timeout=90s 2>&1 | grep -av memcache | tail -1
sleep 15
echo "=== fresh operator logs ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=30 2>&1 | grep -av memcache \
  | grep -ivE '/src/main|controller-runtime@|sigs.k8s.io|processNextWorkItem|reconcileHandler|Start.func|\.Reconcile$' | tail -12
echo "=== wait for Ready flip ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1; trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
for i in $(seq 1 10); do
  P=$(kc "root:orgs:$ORG_NAME:$ACCOUNT_NAME" -n default get aitrustplatforminstance "$INSTANCE_NAME" -o jsonpath='{.status.phase}/{.status.ready}' 2>/dev/null)
  echo "  status=$P"
  [ "$P" = "Ready/true" ] && { echo ">>> READY <<<"; break; }
  sleep 18
done
