#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
git config user.name "mircea" 2>/dev/null; git config user.email "mircea.craciun@sap.com" 2>/dev/null
git add -A
git commit -F - <<'MSG'
Code-review fast-follows: fail-closed tenant_clause fallback + remove worker dead code

From an independent strict code review (no blockers/majors; these were the two MINOR items).

- libs/clickhouse tenant_clause(): the ImportError fallback previously defaulted
  _TENANCY_MODE="single" → "1=1" (no filter) if libs/tenancy were ever absent — a latent
  fail-OPEN. Now: if the tenancy lib is not importable, fail-CLOSED ("1=0") UNLESS the env
  explicitly sets TENANCY_MODE=single. A multi-tenant service that lost the dependency can
  no longer silently return every tenant's rows.
- policy-checker-worker evaluate_all_tenants(): removed the trailing `tenant_id_var.set(None)`
  block that had no evaluate_once() after it (dead + misleading). Shared/catalog (NULL) rows
  are already visible during every tenant pass via the RLS USING clause; a separate pass would
  also double-fire shared-rule alerts. Docstring corrected.
MSG
git log --oneline -3
echo DONE
