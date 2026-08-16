# Design — AI Trust Platform uses the Mesh Keycloak + OpenFGA (per-tenant realm + store)

Status: **DESIGN / documented for later implementation** (not built yet). Supersedes the app's own
per-instance Keycloak. Author basis: live read-only investigation of the mesh IdP on shoot `ai-trust-1`
(2026-08-12) — realm/store facts below are observed, not assumed.

## ADDENDUM (2026-08-13) — app roles discovered on GitHub + the merge decision

**The app DOES have a full RBAC role model** — it lives in the GitHub repo
`AI-Trust-Services/ai-trust-platform` (the local checkout was stale). Source of truth for installs is now
git (see memory `aitrust-app-source-is-github`). The model:
- **6 built-in roles** (`libs/authorization/ai_trust_authorization/constants.py` → `ROLE_PERMISSIONS`):
  `platform_administrator` (all), `ai_engineer`, `ai_compliance_officer`, `business_owner`, `auditor`,
  `executive`. Plus **custom roles** (Postgres `custom_roles` table `ROLE-*` + OpenFGA tuples, managed by
  `users/backend/app/routers/custom_roles.py`, requires `iam:manage`).
- **13 permissions** (`resource:action`) → OpenFGA relations `can_*` on a single **`platform:global`**
  object (mapping in `RELATION_BY_PERMISSION`).
- **Auth vs authz are hard-separated** (git CLAUDE.md): **Keycloak = authentication only** (never realm
  roles for features); **OpenFGA = authorization only**. Backends use `require_permission()`
  (`permissions.py`) reading `X-Forwarded-Preferred-Username` from oauth2-proxy → OpenFGA `check`.
- The app's `infra/openfga-provision/provision.py` builds the FGA model FROM `constants.py` (types
  `user`, `role`, `platform`; each `can_*` relation directly assignable to `role#member`), creates a store
  named `ai-trust`, seeds `role:<name>#member → can_* → platform:global` tuples, and (if
  `INITIAL_ADMIN_USER`) assigns `user:<admin> → member → role:platform_administrator`. Backends read the
  store id from `/config/store_id` (or env `OPENFGA_STORE_ID`), `OPENFGA_URL` for the endpoint.

**DECISION — "merge app roles into the mesh OpenFGA" = per-tenant app store in the SHARED mesh OpenFGA
instance (Option B), NOT editing the mesh's account store.** Rationale:
- OpenFGA has ONE authorization model per store, and the mesh's per-account store model is **owned by the
  mesh Store reconciler** (`spec.coreModule`, finalizers) — writing a merged model directly would be
  reverted on reconcile (a Flux-style fight), and editing the mesh Store CR per tenant is invasive.
- The app's provisioner already creates + owns its own store/model. So: point the app at the **mesh's
  OpenFGA instance** (`openfga.platform-mesh-system.svc:8080`) and give each tenant its **own app store**
  named `ai-trust-<tenant>` (tenant = the mesh/APO account id). This satisfies "use the mesh's OpenFGA" (one
  shared instance) AND "each tenant has its own, non-interacting" (separate store per tenant → tuples in one
  store are invisible to another). No mesh-CR edits, no reconciler fight.
- Keycloak stays exactly as the design below: **mesh realm per tenant, auth only**. The app's roles are
  NOT Keycloak roles (per the app's own hard separation) — they are OpenFGA tuples in the per-tenant app
  store. Identity flows from the mesh realm's token (`preferred_username`/`email`) → oauth2-proxy header →
  the app's OpenFGA check against that tenant's app store.

**Implementation shape:**
- Adapt `openfga-provision` to target the mesh OpenFGA (`OPENFGA_URL=http://openfga.platform-mesh-system:8080`)
  and a per-tenant store name (`OPENFGA_STORE_NAME=ai-trust-<tenant>`); `INITIAL_ADMIN_USER` = the tenant's
  bootstrap admin. It creates the store + app model + role tuples (idempotent) — exactly what it already does,
  just against the mesh instance with a tenant-scoped store name.
- The shared MT app's backends get `OPENFGA_URL` = mesh openfga svc; the store id is resolved per tenant.
  (In the shared-app-multi-tenant runtime, the store must be selected per REQUEST by tenant — see Open items;
  simplest first cut: one app store shared by the shared-app instance keyed to the subscription, matching the
  current single-store `/config/store_id` model, with tenant data isolation still enforced by Postgres RLS.)
- The **subscription operator**, per Subscription, runs an `openfga-provision` Job against the mesh OpenFGA
  with `OPENFGA_STORE_NAME=ai-trust-<tenant>` + `INITIAL_ADMIN_USER=<tenant admin>` — replacing the blocked
  per-tenant-Keycloak-realm job. Keycloak realm provisioning is handed to the mesh (realm already exists per
  org); the operator only needs to ensure the app OIDC client in that realm + seed the app store.

The sections below (mesh realm/store facts, auth binding, integration seam) remain the reference.

## ADDENDUM 2 (2026-08-13) — OpenFGA store scoping DECISION: ONE shared app store, RLS isolates data

**Decision (user-confirmed):** the shared MT app uses **ONE app OpenFGA store `ai-trust`** in the shared
mesh OpenFGA instance — NOT one store per tenant. Seeded ONCE at deploy time by `openfga-provision` run
from `3b-shared-app.sh` (against `OPENFGA_URL=http://openfga.platform-mesh-system.svc.cluster.local:8080`,
`OPENFGA_STORE_NAME=ai-trust`). The resolved store id is written to the app backends' `OPENFGA_STORE_ID`
env (the app's `openfga_client` prefers the env over the `/config/store_id` file, so no shared volume is
needed in k8s).

**Why one store, not per-tenant:**
- The app runs a single backend set with a single `OPENFGA_STORE_ID`; it has no per-request store
  selection. Per-tenant stores would require app changes that don't exist yet.
- Isolation model: **the ROLE/PERMISSION graph is shared across tenants** (all tenants offer the same 6
  built-in roles + any custom roles), but **tenant DATA is fully isolated by Postgres RLS** (`tenant_id` =
  the mesh account id) + ClickHouse/MinIO scoping. So a user of tenant A being `ai_compliance_officer`
  grants the same *permissions* as in tenant B, but each only ever sees their own tenant's rows. Authorization
  (what actions) is shared; data (which records) is isolated. This is the correct separation for a shared app
  where the permission model is identical per tenant.
- Consequence to note: role ASSIGNMENTS (user→role tuples) live in the one store, so an `iam:manage` user
  administering roles operates on the shared store. If per-tenant role isolation is later required, migrate to
  per-tenant stores + add per-request store selection to the app (the app's openfga_client already supports
  `OPENFGA_STORE_ID` env, so the change is: resolve the tenant's store id per request).

**Implementation:** `openfga-provision` runs in `3b-shared-app.sh` (not the subscription operator). The
operator's per-Subscription work stays Keycloak-tenant-realm oriented. The `openfga-provision-job.tmpl` in
the operator is retained for a future per-tenant-store variant but is NOT used in the one-store model.


---

## 1. The model (confirmed with the user)

- The AI Trust Platform app **uses the Mesh's Keycloak + OpenFGA** — it does **not** run its own.
- There is **ONE shared mesh Keycloak** and **ONE shared mesh OpenFGA**.
- **Each tenant is fully isolated inside them**: its **own Keycloak realm** + its **own OpenFGA store**.
  Tenants never interact — separate realms (separate user sets, separate tokens) and separate stores
  (separate authorization data). "Each tenant has its own Keycloak + OpenFGA" = its own **realm + store
  within the shared mesh instances**, not separate IdP deployments.
- **What we add:** the AI Trust app's **roles/permissions are merged INTO each tenant's mesh realm + mesh
  store** — so the mesh becomes the single source of identity + authorization for the app, per tenant.

This is the natural fit because the mesh **already** provisions a realm + store per org account (evidence
below), keyed to the same account id we already use as the app's `tenant_id`.

---

## 2. What the mesh already gives us (observed on ai-trust-1)

**Shared instances (ns `platform-mesh-system`):** Keycloak StatefulSet `keycloak` (pod `keycloak-0`, path
`/keycloak`, svc `keycloak-service:8080`); `openfga` (v1.14.0, svc `openfga:8080` HTTP / `:8081` gRPC,
postgres-backed); plus `iam-service`, `keycloak-operator`, `account-operator`, `rebac-authz-webhook`.

**Realm per ORG** (not per child-account, not one-shared-realm-with-groups). Real realms found:
`welcome` (bootstrap), `master`, and one per org: `demo, aitrustdemo, aitrustg2, aitrust, poc, …`. The
realm name == the org Account name. Realm `aitrust` already exists (matches our `ORG_NAME=aitrust`) with
a confidential portal client (redirect `https://aitrust.ai-trust-1.…/*`) and a public dev client.

**OpenFGA store per ORG.** Stores are `stores.core.platform-mesh.io` CRs in the kcp `root:orgs` workspace
(one per org, name == org). Each Store CR carries `spec.coreModule` (the OpenFGA authz-model DSL) +
`spec.tuples` (seed tuples), and its `status` has the real `storeId` + `authorizationModelId`. One store
covers the whole org subtree (the child `:tenant` workspace reuses it).

**Roles are OpenFGA relations, NOT Keycloak realm roles.** Canonical roles come from configmap
`iam-service-roles` → `roles.yaml`, keyed by `groupResource`:
```yaml
roles:
- groupResource: core.platform-mesh.io/Account
  roles: [{id: owner}, {id: member}]
- groupResource: Namespace
  roles: [{id: owner}, {id: member}]
```
The Store reconciler turns each `groupResource` block into an FGA type with `owner`/`member` relations +
per-k8s-verb permissions. A user is granted a role via a tuple
`role:<fgaType>/<kcpCluster>/<account>/<roleId>` — relation `assignee` → `user:<email>`; the resource then
derives `owner`/`member` from that role's assignees. Identity is keyed on the **`email`** JWT claim
(`iam-service --jwt-user-id-claim=email`).

**Authentication binding per org.** A `WorkspaceAuthenticationConfiguration` per org (kcp `root:orgs`, name
== org) binds the org subtree to issuer
`https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak/realms/<org>`, audiences =
that realm's client ids, username claim = `email`.

---

## 3. Target integration (what MT must change)

### 3a. Authentication — app consumes the tenant's mesh realm
- **Drop** the app's own Keycloak + `keycloak-provision` + the per-tenant-realm provision Job entirely
  (this is what's currently blocked — and correctly so, it's being removed).
- Point each tenant's **oauth2-proxy** at the mesh realm:
  - `--oidc-issuer-url = https://<mesh-host>/keycloak/realms/<tenant-org>` (in-cluster:
    `http://keycloak-service.platform-mesh-system:8080/keycloak/realms/<org>` for redeem/jwks).
  - `--client-id` = the tenant realm's app client (create ONE app client per tenant realm — see 3c).
  - The token already carries usable claims; the app's `tenant_id` = the org/account id (unchanged), and
    the `tenant_id` claim can be a hardcoded-claim mapper on the app client (as our Stage-A provisioner
    already does), OR derived from the realm/issuer. **Preferred:** map `tenant_id` = the mesh account id.
- The app's `JwtClaimResolver` (Stage A `libs/tenancy`) already reads a `tenant_id` claim — unchanged. Only
  the issuer/realm source moves from app-Keycloak to mesh-Keycloak.

### 3b. Authorization — app consumes the tenant's mesh OpenFGA store
- The app checks permissions against the shared OpenFGA (`openfga.platform-mesh-system:8081` gRPC), using
  the tenant's **storeId** (resolve at provision time from `kc root:orgs get store <org>
  -o jsonpath='{.status.storeId}'`; store on the app side as needed).
- Two levels:
  1. **Coarse (no mesh change):** reuse the account `owner`/`member` relations already seeded → map
     `owner`→app-admin, `member`→app-viewer. Works immediately.
  2. **Fine-grained (app roles like compliance-officer, auditor):** add a `groupResource` block for the app
     to the roles source so the Store model emits app-specific FGA types + roles.

### 3c. Merging the app's roles into each tenant (the core ask)
The AI Trust app's role set (to be enumerated — e.g. `admin`, `compliance-officer`, `auditor`, `viewer`)
gets registered per tenant by, at subscribe/provision time:
1. **Realm side:** create an app OIDC client in the tenant's mesh realm `<org>` (redirect URIs = the
   tenant's app host) with a `tenant_id` claim mapper. (Optionally, if any roles must be Keycloak realm
   roles, create them here — but prefer OpenFGA per the mesh convention.)
2. **Store side:** contribute the app's roles as a `groupResource` block (e.g.
   `sub.aitrust.msp/Subscription` or an app-scoped resource) into the mesh role definition so the tenant's
   Store model includes app roles; then write `assignee` tuples binding the tenant's users to app roles.
   - Cleanest: extend the **`iam-service-roles` roles.yaml** with the app's `groupResource` (a mesh-level,
     reviewed change) so EVERY org store gets the app types; per-tenant we then only write user→role tuples.
   - Alternative (no mesh-config change): write the app role types/tuples directly into the tenant store via
     the OpenFGA API at provision time (heavier, per-store model management).

### 3d. Who does the provisioning
The **subscription operator** (already built) changes: instead of stamping a per-tenant-realm Keycloak Job,
on `Subscription` reconcile it (a) ensures the app client exists in the tenant's mesh realm, (b) resolves the
tenant's OpenFGA storeId, (c) writes the app-role tuples, (d) writes the tenant's login URL (mesh realm) to
status. It needs read access to `stores.core.platform-mesh.io` (storeId) + the mesh Keycloak admin (client
creation) + OpenFGA write. This replaces the `tenant-provision-job.tmpl` approach.

---

## 4. Isolation guarantees (why tenants don't interact)
- **Auth:** separate realms ⇒ separate user directories + tokens; a tenant-A token is issued by realm A and
  is not valid for realm B's app client (audience/issuer mismatch).
- **AuthZ:** separate OpenFGA stores ⇒ a tuple in store A is invisible to a check against store B.
- **Data:** unchanged from Stage A — `tenant_id` (= account id) + Postgres RLS + ClickHouse/MinIO scoping.
- **Compute:** the shared app runs on the dedicated `ai-trust` worker pool; per-tenant isolation is data
  + identity, not separate app copies.

---

## 5. Open items to resolve before implementing
- **Enumerate the AI Trust app's actual roles** (grep the app for role/permission concepts — today the app
  is auth-blind past oauth2-proxy, so "roles" may need defining as part of this work).
- **Decide role representation:** OpenFGA relations (mesh-native, recommended) vs Keycloak realm roles.
- **iam-service-roles change is mesh-level** (affects all orgs) — needs review; vs per-store direct writes.
- **App client per tenant realm:** naming, redirect URIs, the `tenant_id` claim mapper.
- **oauth2-proxy issuer per tenant:** one oauth2-proxy per tenant host, or a single one that resolves realm
  by host — design when implementing.
- Confirm the mesh Keycloak admin credential access path for the operator (secret `keycloak-admin`).

---

## 6. Evidence / references
Mesh objects (ns platform-mesh-system): `keycloak-0`, secret `keycloak-admin`, svc `keycloak-service:8080`
(path `/keycloak`); `openfga` svc `:8080/:8081`; configmap `iam-service-roles`; deploys `iam-service` v0.18.0
(`--roles-file-path=/roles/roles.yaml --jwt-user-id-claim=email`), `account-operator` v0.15.4,
`rebac-authz-webhook` v0.10.1 (`--openfga-addr=openfga:8081`). kcp `root:orgs`:
`stores.core.platform-mesh.io` (per-org, e.g. `aitrust` storeId `01KZVNHGWP27BANHPKTB3RNWEB`),
`workspaceauthenticationconfigurations.tenancy.kcp.io` (per-org, issuer `…/keycloak/realms/<org>`),
`invites.core.platform-mesh.io`. Realm names: welcome, master, demo, aitrustdemo, aitrustg2, aitrust, poc.
Investigation scripts: `Standard_AiTrust_MT_MSP/.state/q*.sh`.
