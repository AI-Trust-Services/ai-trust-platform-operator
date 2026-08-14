#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
git add -A
git commit -F - <<'MSG'
Harden multi-tenancy: fix cross-tenant vulns from issue #16 audit

Remediates the security/correctness findings from the issue #16 tenancy audit
(app-repo scope; mesh/deploy items excluded). Builds on the 26722fc foundation.

CRITICAL
- SEC-C1: X-Tenant-Id is no longer client-forgeable. resolver honors the header
  ONLY in `header` mode (trusted-proxy); in jwt mode the tenant comes solely from
  the verified token. shell/nginx.conf strips inbound X-Tenant-Id on all /api/*.
- SEC-C2: JWTs are now cryptographically verified (PyJWT + JWKS: RS256 signature,
  exp, and issuer allowlisted via TENANCY_JWKS_ISSUER_BASE) instead of blind-decoded.
  Fail-closed to 401 on any failure.
- SEC-C3: ClickHouse (gen_ai_spans, alert_events) gains a tenant_id column
  (migration 0003); every read is scoped via ai_trust_clickhouse.tenant_clause()
  (fail-closed in jwt mode), the consumer stamps tenant_id from the OTLP resource
  attr ai_trust.tenant_id, and the worker stamps it on alert_events. MinIO evidence
  object keys are tenant-prefixed (t/<tenant_id>/evidence/...).

HIGH / MEDIUM
- SEC-H1/2/3: shell/nginx.conf sets CSP frame-ancestors 'self' (+ X-Frame-Options
  SAMEORIGIN), HSTS, X-Content-Type-Options nosniff, Referrer-Policy, and drops the
  wildcard CORS on the authenticated app. (Luigi MFEs are same-origin, still frame.)
- SEC-H4: tenancy/isolation tests (libs/tenancy/tests): resolver unit tests
  (X-Tenant-Id ignored in jwt mode, unsigned/wrong-issuer -> None, iss fallback,
  config fail-fast) + RLS write-own integration test.
- SEC-M1: migration 0010 tightens RLS WITH CHECK to write-own
  (tenant_id = current_setting(...)) so a tenant can read shared/catalog (NULL) rows
  but can no longer write NULL or another tenant's rows.
- SEC-M4: security_preflight.check_no_default_secrets() refuses to boot on known
  default credentials when TENANCY_MODE != single.
- config.validate() fail-fasts on an invalid TENANCY_MODE or a jwt-mode deploy
  missing TENANCY_JWKS_ISSUER_BASE.

DOCS (issue #16 AC1/AC5)
- docs/adr/adr-001-tenancy.md: tenant_id = the Platform Mesh account id, aligns with
  the APO account structure; records out-of-scope follow-ups.
- docs/tenancy-model.md: the request -> resolver -> RLS/ClickHouse/MinIO flow.

New env (jwt mode): TENANCY_JWKS_ISSUER_BASE (required), TENANCY_JWT_AUDIENCE,
TENANCY_JWT_VERIFY. Apply pg migration 0010 + clickhouse migration 0003 on deploy.
See updategit.md for the full file-by-file record.
MSG
echo "=== commit result ==="
git log --oneline -2
echo "=== tree clean now? ==="
git status --short | head
echo DONE
