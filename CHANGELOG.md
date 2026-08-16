# Changelog

All notable changes to the AI Trust Platform MSP Operator.

## v4 (0.4) — 2026-08-16 — Rename "AI Trust Platform MT" → "AI Trust Platform" + clean-deploy fixes

Full rename of the provider (display name AND technical identifiers), plus fixes so a fresh
from-scratch deploy is clean. Done via destroy-then-redeploy (fresh provider, discard tenant data).

### Renamed (old → new)
- Display name `AI Trust Platform MT` → **`AI Trust Platform`**
- Namespace `aitrust-mt-msp` → `aitrust-msp` · API group `sub.aitrustmt.msp` → `sub.aitrust.msp`
- kcp ws `root:providers:ai-trust-mt` → `root:providers:ai-trust` · worker pool `ai-trust-mt` → `ai-trust`
- Host `ai-trust-mt[-<org>].<suffix>` → `ai-trust[-<org>].<suffix>` · operator image → `aitrust-operator`
- Chart dirs `aitrust-app` / `aitrust-pm-app` · CRD `subscriptions.sub.aitrust.msp`
- Ops console moved to its own namespace `aitrust-ops`

### Fixed (a fresh deploy previously broke on these)
- Added `TENANCY_JWKS_ISSUER_BASE` (overlay + users-backend env) — app fail-fasts without it in jwt mode.
- Added `USERS_BACKEND_CLIENT_SECRET` env to the keycloak-provision Job.
- Keycloak `postStart` sets master `sslRequired=NONE` (CGNAT pod IPs → 403 HTTPS-required on admin token).
- `3b` OpenFGA store-id: store name `aitrust`, paginated exact-match, injected into operator + backends
  (was shipping `__OPENFGA_STORE_ID__` → nav showed only Overview; seedAdminTuple skipped).
- `patch_syncagent_hostalias` → merge-patch (idempotent). `reset.sh` sweeps stale ClusterRoles +
  PublishedResources so a re-deploy after reset is clean.

## v3 (0.3) — 2026-08-14 — Multi-tenant MSP variant

Release version **3**. This release makes the multi-tenant (MT) MSP variant the
content of `main`, imported from `Standard_AiTrust_MT_MSP`.

### What was done
- **Imported the multi-tenant MSP variant** (`Standard_AiTrust_MT_MSP`) as the
  authoritative content on `main`, overwriting the earlier single-tenant operator layout.
- **Operator (Go):** multi-tenant reconciler — `operator/main.go` + `operator/helpers.go`;
  per-tenant/per-org provisioning manifests under `operator/manifests/`
  (`tenant-provision-job.tmpl`, `keycloak-client-job.tmpl`, `oauth2-proxy-org.tmpl`,
  `openfga-provision-job.tmpl`).
- **Helm charts:** `charts/aitrust-app` (workload side: operator + syncagent + portal)
  and `charts/aitrust-pm-app` (kcp side: APIExport, ContentConfiguration,
  ProviderMetadata, bind RBAC); `subscription` CRD replaces the prior per-instance CRD.
- **Config:** shared-app manifests (`config/shared-app/01-cm-pg-init-mt.yaml`,
  `02-secret-config-mt.tmpl`) for the shared multi-tenant deployment;
  `config.env` targets `aitrust-operator` / image tag `aitrust`.
- **Scripts:** MT deploy pipeline — `2b-build-app-images.sh`, `3b-shared-app.sh`,
  `6-create-subscription.sh` (replaces `6-create-instance.sh`).
- **Docs:** `docs/mesh-idp-integration-design.md`, `msp_aitrust_mt_howto.md`.
- **imagePullPolicy: Always** retained on all app/job/worker containers so deploys
  always pull the latest build (from v0.2).
- Added `.state/` audit, remediation, and verification scripts produced during MT
  bring-up (JWT mode, MinIO rotation, frontend header fix, tenant/health re-audits).

### Tags
- `v0.3` points at this release. Prior tags: `v0.1` (initial investigation),
  `v0.2` (imagePullPolicy: Always), `multitenancy` (first MT import).

## v0.2 — imagePullPolicy: Always
Set `imagePullPolicy: Always` on all app/job/worker containers so deploys always
pull the latest build under the current image tag.

## v0.1 — Initial Investigation
Initial import of the AI Trust Platform MSP operator (single-tenant layout),
operator + charts + config + deployment scripts.
