#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== simulate a tenant-scoped request against overview /v1/stats (set tenant like the middleware does) ==="
kubectl -n "$NS" exec deploy/overview-backend -- sh -lc 'python - <<PY 2>&1 | head
import asyncio
from ai_trust_tenancy import tenant_id_var
tenant_id_var.set("mirceatest")
from ai_trust_persistence import SessionLocal
from sqlalchemy import text
async def go():
    async with SessionLocal() as s:
        # this transaction should SET app.current_tenant=mirceatest via the hook, no error
        r=await s.execute(text("SELECT current_setting(\x27app.current_tenant\x27, true)"))
        print("app.current_tenant in txn =", r.scalar())
        r2=await s.execute(text("SELECT count(*) FROM ai_systems"))
        print("ai_systems visible to mirceatest:", r2.scalar())
asyncio.run(go())
PY' 2>&1 | grep -avi memcache | head
echo "=== recent overview logs: any 500/error on real /v1 endpoints? ==="
kubectl -n "$NS" logs deploy/overview-backend --tail=30 2>&1 | grep -avi memcache | grep -iE 'v1/stats|v1/compliance|500|error|unresolved' | tail -6
echo "(empty = clean)"
echo DONE
