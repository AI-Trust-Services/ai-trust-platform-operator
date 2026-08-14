#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
git config user.name "mircea" 2>/dev/null; git config user.email "mircea.craciun@sap.com" 2>/dev/null
git add -A
git commit -F - <<'MSG'
Close re-audit gaps: ClickHouse UPDATE scoping, frontend headers, FORCE RLS

An independent re-audit of the issue #16 remediation found three residual gaps;
this closes them.

- SEC-C3 (ClickHouse mutations): the alert_events UPDATEs were scoped on WHERE id
  only. Since event ids are global UUIDs, a tenant could handle/approve/reject/resolve
  another tenant's alerts. Added tenant_clause() to all four mutations:
  alerts.py handle_alert_event / approve_model_change / reject_model_change and
  policy-checker-worker resolve_event. Fail-closed (1=0) when no tenant.
- SEC-H1/2/3 (headers): the 7 frontend nginx.conf still emitted X-Frame-Options
  ALLOWALL / CSP frame-ancestors * / Access-Control-Allow-Origin *, which passed
  through the shell proxy and won. Replaced with X-Frame-Options SAMEORIGIN +
  CSP frame-ancestors 'self' and removed wildcard CORS (MFEs are same-origin via
  the shell). Luigi framing still works.
- SEC-M1 (RLS enforcement): migration 0011 adds FORCE ROW LEVEL SECURITY to the 11
  tenant tables (defense-in-depth so RLS applies to the table owner too). Documented
  in ADR-001 the MANDATORY requirement that runtime connects as the non-superuser
  ai_trust_app role (superuser bypasses RLS regardless) and how to verify it on deploy.
MSG
git log --oneline -4
echo DONE
