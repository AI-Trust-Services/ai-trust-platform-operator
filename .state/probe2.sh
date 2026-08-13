#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
line(){ echo "== $1 =="; }

line "A. Any tenancy/tenant_id references anywhere in the running registry app code?"
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc '
grep -rlE "tenant_id|TENANCY_MODE|TENANT_CLAIM|app.current_tenant|install_tenant|tenant_middleware|SET LOCAL" /app 2>/dev/null | grep -viE "[.]pyc" | head -20
echo "--- grep count of tenant hits ---"
grep -rEc "tenant" /app 2>/dev/null | grep -viE ":0$|[.]pyc" | head -20
' 2>&1 | grep -avi memcache | head -30

line "B. database.py — is there SET LOCAL app.current_tenant / after_begin listener?"
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc '
F=$(find /app -path "*ai_trust_persistence*database.py" 2>/dev/null | head -1); echo "file: $F"
[ -n "$F" ] && grep -nE "current_tenant|after_begin|event.listen|SET LOCAL|install_tenant|tenant" "$F" | head -20
' 2>&1 | grep -avi memcache | head -25

line "C. Do the RLS policies actually block, given current_setting is never set? (a table policy)"
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tA -c "
SELECT tablename||'\'' :: '\''||policyname||'\'' :: '\''||qual FROM pg_policies WHERE schemaname='\''public'\'' LIMIT 6;
"' 2>&1 | grep -avi memcache | head -12

line "D. row counts by tenant_id in ai_systems (is data actually stamped with a tenant?)"
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tA -c "
SELECT COALESCE(tenant_id,'\''<null>'\''), count(*) FROM ai_systems GROUP BY 1;
" 2>&1' 2>&1 | grep -avi memcache | head -10
echo DONE
