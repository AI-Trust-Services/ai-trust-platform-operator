#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
echo "=== ns $NS ==="
sk get ns "$NS" 2>&1 | grep -av memcache
echo "=== deploy/job/pods in $NS ==="
sk -n "$NS" get deploy,job,pods 2>&1 | grep -av memcache | head -45
echo "=== operator: newest reconcile lines (after latest restart) ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=60 2>&1 | grep -av memcache \
  | grep -ivE 'controller-runtime@|/src/main.go|processNextWorkItem|reconcileHandler|Start.func|Reconcile$|sigs.k8s.io|Starting|metrics' | tail -14
echo "=== instance phase/url/ns ==="
setup_kcp; kcp_portforward; trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
kc "root:orgs:$ORG_NAME:$ACCOUNT_NAME" -n default get aitrustplatforminstance "$INSTANCE_NAME" \
  -o jsonpath='phase={.status.phase} ready={.status.ready} ns={.status.namespace} url={.status.url}{"\n"}' 2>&1 | grep -av memcache
