#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== users-backend logs: recent 403 / permissions / tenant / authz lines ====="
kubectl -n "$NS" logs deploy/users-backend --tail=120 2>&1 | f | grep -iE 'permission|/me|403|401|tenant|authz|denied|forbidden|jwt|resolver|correlation' | tail -40

echo; echo "===== compliance-backend (also 403? it serves /api/compliance which the log shows called) ====="
kubectl -n "$NS" logs deploy/compliance-backend --tail=60 2>&1 | f | grep -iE '403|401|denied|tenant|jwt|/v1/' | tail -15

echo; echo "===== overview-backend (the /overview/ iframe itself got 403 — is that the BACKEND or the frontend nginx?) ====="
kubectl -n "$NS" logs deploy/overview-backend --tail=40 2>&1 | f | grep -iE '403|401|denied|tenant|/v1/' | tail -15
echo DONE
