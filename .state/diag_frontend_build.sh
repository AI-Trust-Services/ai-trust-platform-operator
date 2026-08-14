#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== users-frontend image + when built ====="
kubectl -n "$NS" get deploy users-frontend -o jsonpath='image={.spec.template.spec.containers[0].image}{"\n"}' 2>&1 | f

echo; echo "===== grep the SERVED bundle for VITE_USERS_API_BASE (is it baked or literally missing?) ====="
kubectl -n "$NS" exec deploy/users-frontend -- sh -c 'grep -rIl "VITE_USERS_API_BASE\|Missing required environment" /usr/share/nginx/html 2>/dev/null | head; echo "---"; grep -rhoE "api/users/v1|/api/users|VITE_USERS_API_BASE" /usr/share/nginx/html/assets/*.js 2>/dev/null | sort -u | head' 2>&1 | f

echo; echo "===== compare: a WORKING frontend (compliance) — is ITS api base baked? ====="
kubectl -n "$NS" exec deploy/compliance-frontend -- sh -c 'grep -rhoE "api/compliance/v1|VITE_COMPLIANCE_API_BASE|Missing required environment" /usr/share/nginx/html/assets/*.js 2>/dev/null | sort -u | head' 2>&1 | f
echo DONE
