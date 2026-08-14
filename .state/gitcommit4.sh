#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
git config user.name "mircea" 2>/dev/null; git config user.email "mircea.craciun@sap.com" 2>/dev/null
git add -A
git commit -F - <<'MSG'
Harden SEC-L1 (insecure-JWT opt-in) + document SEC-M2/SEC-L2 follow-ups

Addresses the low/medium items from the 2026-08-14 independent re-assessment
(all prior Critical/High confirmed remediated).

- SEC-L1: TENANCY_JWT_VERIFY=false in jwt mode now requires an explicit
  TENANCY_ALLOW_INSECURE_JWT=true opt-in; otherwise config.validate() refuses to
  start. Prevents accidentally shipping with JWT signature verification disabled.
  Added 2 tests (refuse without opt-in; allow with opt-in).
- SEC-M2 (worker owner connection) and SEC-L2 (legacy NULL-tenant rows) documented
  as deferred deploy/ops follow-ups in ADR-001 (both are deploy-scope / no live data
  at risk; user-confirmed disposition).
MSG
sed -i 's/SEC-L1 — CLOSED in `<this-commit>`/SEC-L1 — CLOSED/' docs/adr/adr-001-tenancy.md
git log --oneline -5
echo DONE
