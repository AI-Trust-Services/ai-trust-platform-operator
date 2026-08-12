#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
echo "=== not-ready deploys in $NS ==="
sk -n "$NS" get deploy 2>&1 | grep -av memcache | awk 'NR==1 || $2!~/^([0-9]+)\/\1$/{}' | awk 'NR==1||($2!="1/1"){print}'
echo "=== HTTPRoutes the operator created on the gateway ==="
sk -n "$GATEWAY_NS" get httproute 2>&1 | grep -av memcache | grep -E "NAME|aitp-|q3c0"
echo "=== wildcard listener present? ==="
sk -n "$GATEWAY_NS" get gateway "$GATEWAY_NAME" -o jsonpath='{range .spec.listeners[*]}{.name}{" "}{end}{"\n"}' 2>&1 | grep -av memcache
echo "=== instance final status ==="
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1; trap 'pkill -f "port-forward.*root-proxy.*6443" 2>/dev/null||true' EXIT
kc "root:orgs:$ORG_NAME:$ACCOUNT_NAME" -n default get aitrustplatforminstance "$INSTANCE_NAME" \
  -o jsonpath='phase={.status.phase} ready={.status.ready} url={.status.url}{"\n"}' 2>&1 | grep -av memcache
