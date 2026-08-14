# Changelog

All notable changes to the AI Trust Platform MSP Operator.

## v4 (0.4) — 2026-08-14 — Physical per-tenant isolation + tenant-aware IAM & logout

Release version **4** (operator image `v18`). Full details in
[`CHANGES_2026-08-14.md`](CHANGES_2026-08-14.md).

### What was done
- **Physical per-tenant isolation across all three stores** (new `operator/manifests/tenant-stores-job.tmpl`,
  a one-shot Job the operator stamps per Subscription and gates `Ready` on):
  - **Postgres:** schema-per-tenant (`tenant_<org>`) + per-tenant NOLOGIN role `t_<org>` (schema-only,
    `WITH INHERIT FALSE`), shared-role direct grants revoked. RLS retained as a backup layer.
    `ai_trust_app` is now `NOINHERIT` (PG16 `inherit_option` gotcha fixed) — hard wall verified live.
  - **ClickHouse:** database-per-tenant (`tenant_<org>`), CH migrations run per tenant; consumer routes
    each span batch to the tenant DB by `ai_trust.tenant_id`; reads fail-closed to legacy `otel`.
  - **MinIO:** bucket-per-tenant (`tenant-<org>`); jwt mode fail-closed when no tenant.
- **Operator (Go, v12→v18):** added the tenant-stores provisioning step + `jobSucceeded` gate +
  `Provisioning` phase; one-subscription-per-org guard (`orgOwner()`); new cfg/env
  (`dbMigrateImage`, `chMigrateImage`, `APP_DB_ROLE`, whitelist domain); `operator/helpers.go`
  adds Keycloak admin-token + realm-existence checks and OpenFGA HTTP helpers.
- **Tenant-aware IAM user management:** users-backend creates users in the tenant's own realm
  (`current_realm()` from the `tenant_id` claim), via mesh Keycloak admin creds
  (`mesh-keycloak-admin` secret, copied by `3b-shared-app.sh`).
- **Per-tenant front-channel logout:** `keycloak-client-job.tmpl` sets post-logout redirect URIs and
  robust client create/update; `oauth2-proxy-org.tmpl` adds `--backend-logout-url`, whitelist domain,
  and `--skip-provider-button`. Fixes the sign-out / post-logout-403 issues.
- **Create form:** dropped the cosmetic Plan field; relabeled Org (one subscription per org).
- Added `CHANGES_2026-08-14.md` (full change log for a clean fresh deploy) and `git_comments.md`
  (issue #16 verification report).

### Note on issue #16 acceptance criteria
This release materially strengthens **AC3 (K8s-level isolation)** — tenant stores are now physically
separated (schema/DB/bucket per tenant) and provisioned as per-tenant Kubernetes Job resources, rather
than relying solely on application-layer RLS. See `git_comments.md` for the prior audit baseline.

### Tags
- `v0.4` points at this release. Prior: `v0.1`, `v0.2`, `v0.3`, `multitenancy`.

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
- **Helm charts:** `charts/aitrust-mt-app` (workload side: operator + syncagent + portal)
  and `charts/aitrust-mt-pm-app` (kcp side: APIExport, ContentConfiguration,
  ProviderMetadata, bind RBAC); `subscription` CRD replaces the prior per-instance CRD.
- **Config:** shared-app manifests (`config/shared-app/01-cm-pg-init-mt.yaml`,
  `02-secret-config-mt.tmpl`) for the shared multi-tenant deployment;
  `config.env` targets `aitrust-mt-operator` / image tag `aitrust-mt`.
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
