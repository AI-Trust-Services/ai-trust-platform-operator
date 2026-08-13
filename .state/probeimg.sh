#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
line(){ echo "== $1 =="; }

line "A. Does the RUNNING registry image have libs/tenancy? and what does resolver.py read?"
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc '
echo "--- tenancy package present? ---"
find / -path "*ai_trust_tenancy*" -name "*.py" 2>/dev/null | head
echo "--- resolver.py (which claim/header) ---"
F=$(find / -path "*ai_trust_tenancy*" -name resolver.py 2>/dev/null | head -1)
[ -n "$F" ] && grep -nE "claim|header|TENANT_CLAIM|X-Tenant|preferred|tenant_id|getenv|environ|class .*Resolver" "$F" | head -30
' 2>&1 | grep -avi memcache | head -40

line "B. middleware.py — how tenant is set + what it 401s on"
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc '
F=$(find / -path "*ai_trust_tenancy*" -name middleware.py 2>/dev/null | head -1)
[ -n "$F" ] && cat "$F"
' 2>&1 | grep -avi memcache | head -60
echo DONE
