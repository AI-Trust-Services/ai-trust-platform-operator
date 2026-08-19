# Federation Developer Guide — AI Trust Platform across two clusters

**Audience:** developers who need to understand, operate, extend, or re-deploy the cross-cluster
federation. **Status:** LIVE and proven end-to-end (2026-08-19), including the Keycloak SSO round-trip.

This guide is self-contained. Per-stage evidence lives in `STAGE-0..6-STATUS.md`; the design rationale is
in `STAGE-3-DESIGN.md`; this file is the "how it all fits + how to run it" reference.

> **Note on where this doc lives:** federation is implemented entirely in this bundle (operator/controller
> + kcp + Keycloak wiring) — the application git repo (`AI-Trust-Services/ai-trust-platform`) was **NOT
> changed**. So this guide lives with the bundle, not in the app repo's `docs/`.

---

## 1. What federation gives you

The "AI Trust Platform" provider runs on the **ai-trust-1** cluster. Federation makes that same provider
**discoverable and enable-able from a SECOND cluster's Marketplace** (here: **ai-trust-prod**), flagged as
coming from the other cluster. It is **purely additive** — nothing about the existing single-cluster setup
on either cluster changes.

- A user in the **consumer** cluster's portal sees a second tile: **"AI Trust Platform (on ai-trust-1)"**.
- Enabling it provisions an **isolated tenant on ai-trust-1** (not on the consumer cluster) and returns a
  URL on the ai-trust-1 domain: `https://ai-trust-fed-<org>.ai-trust-1...`.
- The user's **consumer-cluster identity is brokered** into that tenant (Keycloak OIDC SSO), so they log
  in with their existing account.
- The local provider on each cluster, and every existing tenant, keep working untouched.

**Terminology.** Two roles:
- **Provider cluster** = **ai-trust-1** — where the real app + all federated tenants physically live.
- **Consumer cluster** = **ai-trust-prod** — where the federated tile + the federation controller live.
Both are independent Gardener shoots, each with its own Platform Mesh (kcp) + Keycloak. They are NOT
joined at the control-plane level.

---

## 2. Two design decisions (why it's built this way)

### Decision 1 — provisioning transport = the provider cluster's SHOOT API (NOT kcp exposure)
A **controller on the consumer cluster** holds a **scoped ServiceAccount kubeconfig for the provider
cluster** and provisions tenants there by talking to the provider's **Kubernetes (shoot) API** directly.
- No control-plane change on the provider cluster: its kcp is NOT exposed publicly, no kcp↔kcp sync.
  ai-trust-1 is treated as a plain remote Kubernetes cluster.
- Rejected alternative: exposing the provider's kcp + kcp-to-kcp sync — more invasive, bigger blast radius.

### Decision 2 — identity = Keycloak OIDC IdP brokering (Option A)
Each federated tenant gets a realm `fed-<org>` on the **provider** Keycloak with an OIDC **Identity
Provider** that brokers the **consumer** Keycloak's `<org>` realm. The reciprocal OIDC **client**
(`aitrust-fed-broker`) is registered in the consumer's `<org>` realm. Result: a consumer user logging into
the federated tenant is redirected home to authenticate, then SSO'd into the provider tenant.

---

## 3. Component inventory — what runs where

### On the PROVIDER cluster (ai-trust-1)
| Component | ns | Purpose |
|---|---|---|
| Shared AI Trust app (operator, syncagent, backends, Keycloak, Postgres, ClickHouse, MinIO, portal) | `aitrust-msp` | the real multi-tenant app (deployed by the normal single-cluster install) |
| **ServiceAccount `aitrust-federation`** + scoped RBAC + long-lived token | `aitrust-msp` (+ Role in `platform-mesh-system`) | the credential the consumer controller uses (Stage 1) |
| Per federated tenant: realm `fed-<org>`, schema `tenant_fed_<org>`, role `t_fed_<org>`, CH db `tenant_fed_<org>`, bucket `tenant-fed-<org>`, oauth2-proxy, HTTPRoute `aitrust-fed-<org>` | `aitrust-msp` / `platform-mesh-system` | the provisioned federated tenant |

### On the CONSUMER cluster (ai-trust-prod), ns `aitrust-remote`
| Component | Purpose |
|---|---|
| Secret `aitrust-1-shoot-kubeconfig` | the provider SA kubeconfig the controller mounts (Stage 1) |
| **`aitrust-federation`** Deployment | the federation controller — image `mirceacraciun795/aitrust-federation:aitrust` (Stage 3) |
| **`aitrust-remote-syncagent`** Deployment + PublishedResource | mirrors `sub.aitrust.remote` Subscriptions kcp↔cluster (Stage 3) |
| `aitrust-remote-portal` nginx + ConfigMap | serves the federated tile `pm-content.json` (Stage 2) |

### On the CONSUMER cluster's kcp (prod control plane)
| Object (in ws `root:providers:ai-trust-remote`) | Purpose |
|---|---|
| `APIExport sub.aitrust.remote` | the federated Subscription API |
| `ProviderMetadata` "AI Trust Platform (on ai-trust-1)" | the tile identity |
| `ContentConfiguration aitrust-ui` | points the portal at the `aitrust-remote-portal` tile |

---

## 4. The federation controller — the two-client fork

`federation-operator/` is a fork of the app's `operator/` with a **two-client split**:

| Client | Cluster | Used for |
|---|---|---|
| **local** (`mgr.GetClient()`) | consumer (prod) | watch mirrored `sub.aitrust.remote` Subscriptions, write status, finalizer, duplicate guard; stamp the reciprocal prod-client Job (Keycloak reachable here) |
| **remote** (`REMOTE_KUBECONFIG` → provider SA) | provider (a1) | all tenant provisioning (broker Job, stores Job, kc-client Job, oauth2-proxy, HTTPRoute, secrets) + teardown |

Everything the stock operator did with one client for *provisioning* is redirected to the **remote**
client; everything about the *Subscription object* stays on the **local** client.

**`fed-<org>` namespacing.** Federated tenants are prefixed `fed-` at the provider so they never collide
with the provider's native tenants or a same-named consumer-local tenant. `org = "fed-" + <spec.org>`
flows through everything (realm, host, schema, role, db, bucket).

**Realm gate (important design point).** The stock operator's realm gate does a direct HTTP call to the
mesh Keycloak. The federation controller runs on the **consumer** cluster, but the **provider's** mesh
Keycloak is only reachable by in-cluster DNS **from the provider**. So the controller does NOT re-check
via HTTP — the **broker Job runs ON the provider and its success IS the realm-exists proof** (fail-closed:
no broker success → no provisioning).

---

## 5. End-to-end request flow (what happens on Enable)

```
Consumer portal → Enable "AI Trust Platform (on ai-trust-1)"
  → kcp: Subscription {org:<X>} created in the consumer's account workspace (binds APIExport sub.aitrust.remote)
    → aitrust-remote-syncagent mirrors it DOWN to the consumer cluster (ns = consumer cluster-id)
      → federation controller reconciles (org := fed-<X>):
         1. broker Job ON a1        → realm fed-<X> + OIDC IdP 'prod' (→ prod realm <X>) + tenant_id mapper
         2. tenant-stores Job ON a1 → schema tenant_fed_<X> + role t_fed_<X> + CH db + MinIO bucket
         3. kc-client Job ON a1     → per-tenant oauth2-proxy OIDC client in realm fed-<X>
         4. oauth2-proxy + Service + HTTPRoute ON a1 → host ai-trust-fed-<X>.ai-trust-1...
         5. reciprocal prod-client Job ON prod (local) → client aitrust-fed-broker in PROD realm <X>
            (redirect = a1 broker callback, SAME per-org secret) — completes the SSO loop
      → status.phase=Ready, status.url, status.cluster=ai-trust-1  (synced back UP to kcp)
```

**SSO at login time:**
```
user → https://ai-trust-fed-<X>.ai-trust-1...  (oauth2-proxy on a1, realm fed-<X>)
     → realm fed-<X> IdP 'prod'                 → redirect to PROD Keycloak realm <X>
     → PROD realm <X> client 'aitrust-fed-broker' authenticates the user
     → callback to a1 → user SSO'd into the federated tenant
```

---

## 6. Set up federation from scratch (given both single-cluster installs already exist)

Prereqs: the AI Trust app is already deployed single-cluster on the **provider** (ai-trust-1) and the
**consumer** (ai-trust-prod) has a working Platform Mesh. Garden login fresh
(`prerequisites/login.sh`). All scripts are in this `Federation/` folder.

```bash
# 0. Reachability gate — confirm consumer→provider shoot API is reachable (auth-gated only).
#    (documented in STAGE-0-STATUS.md; a GET /version from a consumer pod should return 401)

# 1. Provider credential: scoped SA on the PROVIDER, kubeconfig stored on the CONSUMER.
kubectl --kubeconfig <provider> apply -f stage1-a1-serviceaccount.yaml
#    build a kubeconfig from the SA token + provider API/CA, then:
kubectl --kubeconfig <consumer> -n aitrust-remote create secret generic aitrust-1-shoot-kubeconfig \
  --from-file=kubeconfig=<sa-kubeconfig>

# 2. Federated tile on the CONSUMER kcp (provider workspace + APIExport + tile nginx).
bash stage2-provider.sh

# 3. Federation controller + syncagent on the CONSUMER.  IMPORTANT: run via the substituting script,
#    NEVER `kubectl apply -f stage3-federation-deploy.yaml` raw (it has __PLACEHOLDER__s).
bash stage3-deploy.sh

# The tile is now enable-able. Stages 4 (a1 IdP broker) and 6 (reciprocal prod client) are FOLDED INTO
# the controller — they run automatically per Subscription. No separate step.
```

Verify: `bash stage5-verify.sh` (invariants) and enable a test org: `bash stage6-reciprocal-test.sh`.

---

## 7. How to add a NEW federated org

Nothing manual on the clusters — it's driven by a Subscription:

1. The consumer org must have a **real Keycloak realm `<org>`** on the consumer cluster (the mesh creates
   one realm per onboarded org). This is the ONLY prerequisite for the SSO round-trip; without it the
   tenant still provisions but the reciprocal client waits (non-fatal).
2. From the consumer portal, **Enable** the "AI Trust Platform (on ai-trust-1)" tile for that org (or
   create a `Subscription {org:<org>}` in the org's account workspace bound to `sub.aitrust.remote`).
3. The controller does the rest: `fed-<org>` realm + IdP broker, per-tenant stores, oauth2-proxy + route,
   and the reciprocal `aitrust-fed-broker` client in the consumer's `<org>` realm.
4. Result: `https://ai-trust-fed-<org>.ai-trust-1...`, status `Ready`, `cluster=ai-trust-1`.

**Disable** (delete the Subscription): the controller removes the oauth2-proxy + HTTPRoute on the
provider; **tenant DATA is preserved** (append-only policy — schema/db/bucket stay).

---

## 8. RBAC the provider SA needs (final set — grew during bring-up)

In `stage1-a1-serviceaccount.yaml`:
- ns `aitrust-msp`: `jobs` (CRUD), `pods`/`pods/log` (read), `secrets` (CRUD — per-org + broker secrets +
  mesh-admin copy), `configmaps` (read), `deployments`/`services` (CRUD), `referencegrants` (CRUD).
- ns `platform-mesh-system`: `httproutes` + `referencegrants` (CRUD), `secrets` (get/list — read the mesh
  keycloak-admin).

The consumer-side controller's own RBAC (in `stage3-federation-deploy.yaml`): watch `sub.aitrust.remote`
subscriptions(+status); and (for the reciprocal client) `jobs`/`secrets` in `aitrust-remote` +
read the consumer mesh keycloak-admin in `platform-mesh-system`.

---

## 9. Gotchas / troubleshooting

- **`kubectl apply -f stage3-federation-deploy.yaml` raw is WRONG** — it re-applies literal
  `__IMG__`/`__A1_DOMAIN_SUFFIX__` and breaks the Deployment (InvalidImageName) + a placeholder-hostname
  HTTPRoute. Always apply through `stage3-deploy.sh` / a sed-substituting wrapper.
- **Garden token lapses often** — re-run `prerequisites/login.sh`; shoot admin kubeconfigs expire ~4h.
  The provider SA token does NOT expire (that's why Stage 1 uses an SA, not a re-minted shoot kubeconfig).
- **Subscription stuck `Degraded: no Keycloak realm`** even though the broker Job succeeded → you're
  looking at the pre-fix behavior; the controller must TRUST the broker Job (it can't reach the provider
  Keycloak by HTTP from the consumer). Ensure the deployed image is the broker-trust build.
- **Reconcile 'not wired yet'** for the reciprocal client is normal on the first pass (the prod-client Job
  takes a few seconds); it flips to **`reciprocal prod-side SSO client wired`** on the next reconcile.
- **Distroless pods** (operator, keycloak) have no shell/curl/python — probe from a backend pod, or read
  a Job's own logs (the broker/client Jobs log their result).
- **Never inline `bash -c` with `$VARs` on WSL** — variables silently empty; write a script file.
- **kcp consumer workspace access:** subscriptions live in the **account** ws
  (`root:orgs:<org>:tenant`, ns `default`), not the org ws. Some orgs' account ws may be Forbidden to a
  given kcp-admin kubeconfig — that's an access scope, not a federation bug.

---

## 10. Files in this folder (map)

| File | What |
|---|---|
| `README.md` | overview + stage table + invariants |
| `FEDERATION-GUIDE.md` | **this guide** |
| `STAGE-0..6-STATUS.md` | per-stage evidence/results |
| `STAGE-3-DESIGN.md` | controller design rationale |
| `stage1-a1-serviceaccount.yaml` | provider SA + RBAC |
| `stage2-*.{sh,yaml,json}` | consumer kcp tile + provider registration |
| `stage3-deploy.sh` + `stage3-federation-deploy.yaml` + `stage3-syncagent.yaml` | controller + syncagent deploy |
| `federation-operator/` | the two-client controller (Go) + Dockerfile + manifests |
| `stage5-verify.sh` / `stage5-teardown-test.sh` / `stage6-reciprocal-test.sh` | tests |
