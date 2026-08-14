#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
git config user.name "mircea" 2>/dev/null; git config user.email "mircea.craciun@sap.com" 2>/dev/null
git add -A
git commit -F - <<'MSG'
Fix tenant session hook: asyncpg paramstyle (%s -> inlined literal)

The `begin` event hook set app.current_tenant via
exec_driver_sql("SELECT set_config(..., %s, true)", (tenant,)), but the raw DBAPI
connection is asyncpg, which uses $1 not %s -> PostgresSyntaxError on every
transaction (health 503, and any tenant-scoped query would fail). The value is a
validated tenant/realm id, so inline it as a SQL literal after checking it against
a safe charset [A-Za-z0-9._:-]{1,64}; reject (no SET -> RLS shows only shared rows,
fail-closed) otherwise. Driver-agnostic, no paramstyle dependency.
MSG
git log --oneline -3
echo DONE
