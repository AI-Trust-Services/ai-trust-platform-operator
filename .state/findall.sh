#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
setup_kcp; kcp_portforward
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done
trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null || true' EXIT
echo "=== EVERY AITrustPlatformInstance on the shoot (all namespaces) — the operator reconciles these ==="
sk get aitrustplatforminstance -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,HOST:.status.url' 2>&1 | grep -av memcache
echo "=== consumer-side CRs (what the syncagent mirrors FROM) ==="
kc root:orgs:aitrustg2:demo -n default get aitrustplatforminstance -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,URL:.status.url' 2>&1 | grep -av memcache
echo "=== operator: recent reconcile hosts (is it still creating d. ?) ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=40 2>&1 | grep -av memcache | grep -oE 'host":"[^"]*|"ns":"aitp[^"]*' | sort -u | tail -15
