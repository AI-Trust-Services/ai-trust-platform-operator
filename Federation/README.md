# Federation — ai-trust-1 ⇄ ai-trust-prod cross-cluster provider

**Goal.** Make the *"AI Trust Platform"* provider that runs on the **ai-trust-1** cluster
**discoverable and enable-able from the ai-trust-prod Marketplace**, flagged as coming from the other
cluster. All existing setups keep working unchanged — this is **purely additive**.

- A prod user browsing the prod portal sees **two** AI Trust tiles: the local prod provider, and a
  **federated** tile badged *"on ai-trust-1"*.
- Enabling the federated tile provisions a **tenant on ai-trust-1** (not on prod) and returns a URL on
  the ai-trust-1 domain.
- A prod user can **SSO into that ai-trust-1 tenant** (identity brokering).
- Enabling the **local** prod tile still provisions on prod exactly as today. Existing ai-trust-1
  tenants and prod-local tenants are untouched.

This folder lives inside the MSP bundle (`Standard_AiTrust_MT_MSP`) on purpose — Stages 2–3 reuse this
bundle's `charts/aitrust-pm-app` + `scripts/3-provider.sh` and the tenant-provisioning templates.

---

## Clusters (both Gardener shoots in garden project `garden-ai-trust`, cc-one showroom)

| Cluster | Shoot | Shoot API server | Role in federation |
|---|---|---|---|
| **ai-trust-prod** | `ai-trust-prod` | `https://api.ai-trust-prod.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu` | **Consumer side** — hosts the federated tile + the federation controller. |
| **ai-trust-1** | `ai-trust-1` | `https://api.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu` | **Provider side** — the real "AI Trust Platform" app + tenants get provisioned here. |

Both run the shared multi-tenant AI Trust app in namespace **`aitrust-msp`** (per-tenant Postgres schema
`tenant_<org>` + role `t_<org>`, ClickHouse db `tenant_<org>`, MinIO bucket `tenant-<org>`; **RLS-free /
tenant_id-free** as of the 2026-08-19 purge — app repo `AI-Trust-Services/ai-trust-platform@mircea-mt2`).

---

## Chosen mechanism (decided with the user)

Two design decisions were locked before implementation:

### 1. Provisioning transport = **ai-trust-1 SHOOT API** (NOT kcp exposure)
A **prod-side controller** holds a **minted ai-trust-1 shoot admin kubeconfig** (a Kubernetes Secret in
prod) and provisions tenants on ai-trust-1 by talking to **ai-trust-1's shoot API directly**.

- **No ai-trust-1 control-plane change.** We do NOT expose ai-trust-1's kcp publicly, and we do NOT add
  a kcp sync relationship. ai-trust-1 is treated as a plain remote Kubernetes cluster.
- The shoot admin kubeconfig is **short-lived (~4h)** → a **refresh mechanism** is required (re-mint via
  the Gardener `AdminKubeconfigRequest`, or a longer-lived scoped ServiceAccount token on ai-trust-1).
  Tracked in Stage 1.
- Rejected alternative: exposing ai-trust-1's kcp publicly + kcp-to-kcp sync. More invasive, changes
  ai-trust-1's control plane, larger blast radius. The user reverted to the shoot-API approach.

### 2. Identity = **Option A, Keycloak IdP brokering**
For a federated tenant, ai-trust-1's per-tenant (org) Keycloak realm is configured with an **OIDC Identity
Provider that brokers prod's Keycloak realm**. A prod user logging into the federated tenant is redirected
to prod's Keycloak (first-login federation), so they SSO into the ai-trust-1 tenant with their prod
identity. Only applied to **federated** tenants; local tenants on either cluster are unaffected.

---

## Stage plan

| Stage | Task | What it does | Status |
|---|---|---|---|
| **0** | #255 | Garden login + mint both shoot kubeconfigs + **confirm prod→ai-trust-1 shoot API is network-reachable** (auth-gated only). Gate for all cluster work. | ✅ **DONE** (see `STAGE-0-STATUS.md`) |
| **1** | #256 | On ai-trust-1: scoped SA + RBAC + long-lived token; stored as Secret `aitrust-1-shoot-kubeconfig` in prod ns `aitrust-remote`. | ✅ **DONE** (`STAGE-1-STATUS.md`) |
| **2** | #257 | Prod kcp `root:providers:ai-trust-remote`: APIExport `sub.aitrust.remote` + ProviderMetadata "AI Trust Platform (on ai-trust-1)" + ContentConfiguration → prod-side tile nginx. Prod-local provider untouched. | ✅ **DONE** (`STAGE-2-STATUS.md`) |
| **3** | #258 | **Federation controller** = fork of the operator with a two-client split (local prod kcp watch + status; remote a1 client for provisioning), `fed-<org>` naming. | ✅ **DONE** — live, E2E proven (`STAGE-3-STATUS.md`) |
| **4** | #259 | **Option A IdP brokering**: a1 `fed-<org>` realm brokers prod's `<org>` realm (OIDC IdP) so prod users SSO into the a1 tenant. Folded into the controller reconcile. | ✅ **DONE** (`STAGE-4-STATUS.md`) |
| **5** | #260 | **E2E verify** + teardown test + docs/memory. | ✅ **DONE** — all 5 invariants pass; teardown preserves data (`STAGE-5-STATUS.md`) |
| **6** | #264 | **Reciprocal prod-side IdP client** — register `aitrust-fed-broker` in prod realm `<org>` (a1 broker redirect + shared secret) so the SSO round-trip completes browser-to-browser. Folded into the controller. | ✅ **DONE** — verified with org `aitrust` (`STAGE-6-STATUS.md`) |

> **STATUS: federation is LIVE and proven end-to-end incl. SSO round-trip (2026-08-19).** A prod-portal
> Enable of the "AI Trust Platform (on ai-trust-1)" tile provisions an isolated tenant on ai-trust-1
> (`ai-trust-fed-<org>.ai-trust-1`, schema/role/DB/bucket, `fed-` prefixed), wires BOTH sides of Keycloak
> SSO (a1 realm `fed-<org>` IdP → prod realm `<org>` client `aitrust-fed-broker`), and returns Ready.
> Works for any org with a real prod realm. Prod-local provider + all existing tenants on both clusters
> unaffected; Disable tears down the login path and keeps data. **Deploy note:** always apply
> `stage3-federation-deploy.yaml` through its sed substitution (never raw — the `__PLACEHOLDER__`s must
> be filled), e.g. via `stage3-deploy.sh`.

---

## Invariants / guardrails

- **Additive only.** The existing prod-local provider, the existing ai-trust-1 provider, and every
  existing tenant on both clusters MUST keep working unchanged at every stage.
- **No ai-trust-1 control-plane change.** Everything ai-trust-1-side is a plain Kubernetes API call via
  the shoot kubeconfig (namespaced resources in `aitrust-msp` + gateway HTTPRoutes). No kcp/APIExport
  changes on ai-trust-1.
- **RLS-free / tenant_id-free provisioning.** Any tenant the controller creates on ai-trust-1 must use
  the current physical isolation only (schema + role + CH db + bucket), matching `mircea-mt2` — never
  recreate the removed `tenant_id` column or RLS.
- **Credentials are short-lived.** The a1 shoot kubeconfig expires ~4h; the controller must refresh it,
  and never assume a static token.

---

## Environment gotchas (learned this project)

- Garden auth uses the `kubectl oidc-login` exec-plugin kubeconfig; the cached token lapses → re-run the
  garden browser login before cluster ops.
- Shoot admin kubeconfigs from `AdminKubeconfigRequest` expire in **~4h** (we mint with
  `expirationSeconds: 14400`).
- **Never inline `bash -c` with `$VARs` on WSL** — the variables silently empty out. Always write a
  script file and run it via `wsl.exe -d Ubuntu -- bash <file>`.
- Distroless pods (e.g. `aitrust-operator`) have **no shell** — probe from a Python/`sh`-capable pod
  (e.g. `compliance-backend`).

---

## Files in this folder

- `README.md` — this file (design + stage plan + invariants).
- `STAGE-0-STATUS.md` — Stage 0 evidence (reachability proof) + what's confirmed done.

> **Mirror note:** this bundle is mirrored to the operator repo (`ai-trust-platform-operator` /
> `Apeirora_MSP_Operator`). When federation code/charts are added here, mirror them too.
