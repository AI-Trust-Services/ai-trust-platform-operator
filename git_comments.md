# Issue #16 — Verification Report

**Issue:** [Adopt Platform Mesh account and tenancy model](https://github.com/AI-Trust-Services/ai-trust-platform/issues/16)
**Repo audited:** `Apeirora_MSP_Operator` @ `main` (MT variant)
**Method:** Automated multi-agent code audit (evidence gathered per criterion, then adversarially adjudicated).
**Result:** **3 MET, 2 PARTIAL.**

> Draft comment for issue #16 — not yet posted (no github.com credential available at audit time).
> Checkboxes below mirror the intended issue-body state: tick AC1, AC2, AC5; leave AC3, AC4 unchecked.

---

## Verification status — code audit against acceptance criteria

- [x] **AC1 — Tenancy model documented + maps to Platform Mesh account hierarchy — MET.**
  `charts/aitrust-mt-app/crds/subscription.yaml:47-58` (`tenantId` = resolved Platform Mesh / APO account id; `org` = mesh account name == Keycloak realm); `README.md:40-42` (Account org → child Account → APIBinding → Subscription → tenant realm); `docs/mesh-idp-integration-design.md:99-118`; `operator/main.go:106-113`.
  *Caveat:* `README.md:65` (tenantId = cr.Namespace, realm `t-<tenantId>`) contradicts the current operator/CRD (org-authoritative) — README should be reconciled.

- [x] **AC2 — Tenant context propagated through all service calls — MET.**
  End-to-end chain verified: operator derives `tenantID` from `spec.org` (`operator/main.go:113`) → Keycloak hardcoded-claim mapper injects `tenant_id` into tokens (`keycloak-client-job.tmpl:63-69`) → per-org oauth2-proxy forwards JWT (`oauth2-proxy-org.tmpl:47-48`) → backends read `TENANCY_MODE=jwt` / `TENANT_CLAIM=tenant_id` (`config/shared-app/02-secret-config-mt.tmpl:48-49`) → app ContextVar → `SET app.current_tenant` per transaction → Postgres RLS. Runtime proofs: `.state/finaltenant.sh`, `.state/rlsproof.sh`. Status echoed back to CR (`operator/main.go:313`).
  *Note:* model is a flat `tenant_id` per account; no nested hierarchy levels are propagated.

- [ ] **AC3 — Multi-tenant isolation enforced at Kubernetes resource level — PARTIAL.**
  Per-tenant K8s resources exist only for the **auth/routing** plane (per-org oauth2-proxy Deployment/Service/HTTPRoute/ReferenceGrant, `operator/manifests/oauth2-proxy-org.tmpl:13-85`). **Data isolation is app-layer only** (Postgres RLS via `tenant_id` claim, `config/shared-app/01-cm-pg-init-mt.yaml:6-19`). Single shared namespace `ai-trust-app` (`config/k8s-app/00-namespace.yaml:2-4`); **no** per-tenant Namespace / NetworkPolicy / ResourceQuota / LimitRange / RBAC anywhere in the repo. K8s-level data/network/compute enforcement is not present.

- [ ] **AC4 — Modular / replaceable tenancy module for enterprise needs — PARTIAL.**
  Config is externalized (`env()`/`cfg()` `operator/main.go:50-87`, Helm values `charts/aitrust-mt-app/templates/operator.yaml:72-93`) and provisioning manifests are decoupled `.tmpl` files via `embed.FS` (`operator/main.go:43-44`). But there is **no** provisioner interface / strategy / `TENANCY_MODE` toggle in the operator — `Reconcile()` (`operator/main.go:94-193`) hardcodes the provisioning pipeline, and `render()` is a plain `strings.ReplaceAll`. `README.md:87` labels the `enterprise` plan a "cosmetic tier label; no per-tenant infra". Swapping tenancy strategies requires editing the Go reconciler.

- [x] **AC5 — Decision documented: alignment with APO account structure — MET.**
  Labeled DECISION sections in `docs/mesh-idp-integration-design.md:27-40, 58-83, 99-100` ("tenant = the mesh/APO account id"; one-shared-store + Postgres RLS with `tenant_id` = mesh account id, marked user-confirmed). Corroborated by `README.md:11-15`.
  *Note:* no standalone ADR file, but the decision + rationale are documented.

---

## Remaining work to fully close

- **AC3:** enforce tenant isolation at the K8s level — per-tenant Namespace / NetworkPolicy / ResourceQuota / RBAC (or equivalent), rather than relying solely on application-layer RLS.
- **AC4:** introduce a pluggable tenancy-provisioner abstraction (interface + selectable implementations + a real `TENANCY_MODE` toggle in the operator) so an enterprise deployment can substitute a different provisioning backend without editing `Reconcile()`.

## Auditor notes / limitations

- Evidence is file:line-cited against the repo as it stands on `main`; please sanity-check before closing.
- The `ai_trust_tenancy` library (ContextVar propagation + SQLAlchemy session hook) and the ClickHouse/MinIO tenant-scoping code live in the **separate app repo**; this repo demonstrates their behavior via runtime proof scripts (`.state/finaltenant.sh`, `.state/rlsproof.sh`) rather than containing the implementation.
- "Hierarchy level" in AC2 is only partially addressed: identity is a single account-scoped `tenant_id`, not a nested multi-level hierarchy.
