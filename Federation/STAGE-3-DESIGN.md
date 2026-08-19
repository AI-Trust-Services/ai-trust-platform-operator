# Stage 3 — federation controller (provision on ai-trust-1)  🔧 IN PROGRESS (authoring)

**Task #258.** The controller runs **on prod**, watches `sub.aitrust.remote` Subscriptions, and
provisions each tenant **on ai-trust-1** (via the Stage-1 SA kubeconfig). Per the agreed plan it is a
**fork of the existing `operator/`** with a **remote provisioning client**, and federated tenants are
**namespaced `fed-<org>`**. This doc is the design; the code lands in `federation-operator/` next to it.

## Two-client design (the core change vs the stock operator)

The stock operator uses one client (`r.Client`) for everything. The federation controller uses **two**:

| Client | Cluster | Used for |
|---|---|---|
| **local** (`r.Client`, controller-runtime manager) | **prod kcp** (via the `sub.aitrust.remote` APIExport, reached by the bundled **sync-agent**) | watch `Subscription` CRs, write `status` (phase/url/cluster/ready), finalizer. |
| **remote** (`r.remote`, built from the mounted a1 SA kubeconfig) | **ai-trust-1** shoot API | apply the tenant-stores Job, kc-client Job, oauth2-proxy + Service + HTTPRoute + ReferenceGrant, org secrets; read Job status; teardown. |

Everything the stock operator does with `r.Client` for *provisioning* (`applyDoc`, `jobExists`,
`jobSucceeded`, `ensureOrgSecret`, `ensureMeshAdminSecret`, `deleteOrgResources`) is redirected to
`r.remote`. Everything about the *Subscription object* (`Get`, `setPhase`/`Status().Update`,
finalizer, `orgOwner` duplicate check) stays on `r.Client`.

## Naming — `fed-<org>` (collision-free with a1's native tenants)

To avoid colliding with ai-trust-1's own local tenants (`fridaytest`, `martin`, …) or a same-named
prod-local tenant, federated tenants get a `fed-` prefix at the a1 layer:

| Thing | Stock operator | Federation controller |
|---|---|---|
| tenant key | `<org>` | `fed-<org>` |
| PG schema / CH db | `tenant_<org>` | `tenant_fed_<org>` |
| MinIO bucket | `tenant-<org>` | `tenant-fed-<org>` |
| PG role | `t_<org>` | `t_fed_<org>` |
| host | `ai-trust-<org>.<a1-suffix>` | `ai-trust-fed-<org>.ai-trust-1.<...>` |
| Keycloak realm | `<org>` (mesh realm) | **a1 org realm** (Stage 4 brokers prod's realm into it) |

The `dnsSafe`/schema/bucket derivations already in the operator are reused with the `fed-` prefix
folded into `org` early in Reconcile.

## Config (env) — points at BOTH clusters

Inherits the stock operator's env, plus:
- `REMOTE_KUBECONFIG=/etc/a1/kubeconfig` — mounted from Secret `aitrust-remote/aitrust-1-shoot-kubeconfig`.
- `PROVIDER_NS=aitrust-msp` (on **a1** — same ns name; the remote client targets a1).
- `INSTANCE_DOMAIN_SUFFIX=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu` (a1 host).
- `GATEWAY_NS=platform-mesh-system`, `GATEWAY_NAME=k8sapi-gateway` (a1's gateway — confirmed Stage 1).
- Keycloak/mesh-admin env point at **a1's** mesh Keycloak (the tenant realm + oauth2-proxy live on a1).
- `gvk` group = **`sub.aitrust.remote`** (not `sub.aitrust.msp`), finalizer renamed to match.
- `status.cluster = "ai-trust-1"` added so the federated tile's Cluster column shows origin.

## Reconcile flow (deltas from the stock operator, in order)

1. Resolve `org` from `spec.org`; **prefix `fed-`**; derive `tenant_fed_<org>` / `tenant-fed-<org>` /
   host `ai-trust-fed-<org>.<a1-suffix>`.
2. Finalizer + one-sub-per-org guard — unchanged, on `r.Client` (prod).
3. Realm gate — checks the realm on **a1's** mesh Keycloak (the tenant realm must exist there; Stage 4
   ensures it + brokers prod).
4. **Per-tenant stores Job → applied to a1** (`r.remote.applyDoc`), gated on `jobSucceeded` **on a1**.
   Reuses `tenant-stores-job.tmpl` verbatim (it references a1's in-cluster `postgres`/`clickhouse`/
   `minio`/`app-secrets` — correct, since it runs on a1). NOTE: the template's comment mentions
   "migration 0012 / RLS dropped" — stale post-purge (head is 0009, RLS never created) but functionally
   correct; will refresh the comment.
5. kc-client Job + oauth2-proxy + HTTPRoute → applied to **a1** on host `ai-trust-fed-<org>.<a1-suffix>`.
6. Status on the **prod** Subscription: phase/url(=a1 host)/cluster=ai-trust-1/ready.
7. Delete → `deleteOrgResources` on **a1** (best-effort; tenant DATA never deleted).

## Sync-agent (makes the Stage-2 APIExport publish `subscriptions`)

The controller ships with an `api-syncagent` (same as `aitrust-app` chart) pointed at prod kcp ws
`root:providers:ai-trust-remote`, publishing the `subscriptions` resource for `sub.aitrust.remote`.
This is what lights up the Stage-2 tile so a prod user can Enable. Reuses the proven syncagent
hostAlias + `bind_authenticated` fixes from `lib.sh`.

## Deploy (prod ns aitrust-remote)
- `federation-operator` Deployment (image `mirceacraciun795/aitrust-federation:<tag>`), mounts the a1
  kubeconfig Secret, env as above, kcp-admin kubeconfig for the manager to watch the provider ws.
- `api-syncagent` Deployment bound to `sub.aitrust.remote`.
- RBAC: read/write Subscriptions + status in the provider ws.

## Build
`federation-operator/` = copy of `operator/` (go.mod, helpers.go, manifests/) + a modified `main.go`
with the two-client split. Build `mirceacraciun795/aitrust-federation:aitrust` via its Dockerfile.

## Status
Design locked (this doc). Code + Dockerfile authored in `federation-operator/`.

**BUILD DONE (2026-08-19):** the two-client fork compiles — `docker build` succeeded inside
`golang:1.23-alpine` (Go type-checks the `clientcmd` import, remote-client wiring, `fed-` prefixing,
`status.cluster`). Image pushed: `mirceacraciun795/aitrust-federation:aitrust`
(digest `sha256:c4ab0a978759e8d6956b2d50e9a7fe5bea167292b3639dff0864b50c7b7fa6dc`).

### Architecture confirmed against the stock chart
The stock operator watches **local mirrored** Subscription CRs (the sync-agent syncs kcp↔local; the
operator uses its in-cluster SA, cluster-scoped RBAC on `sub.aitrust.msp` subscriptions) — it does NOT
dial kcp directly. So the federation controller is the same shape:
- **local client** = `mgr.GetClient()` (in-cluster prod SA) → watches mirrored `sub.aitrust.remote`
  Subscriptions + writes status (synced back to kcp by the sync-agent).
- **remote client** = a1 SA kubeconfig (mounted from `aitrust-remote/aitrust-1-shoot-kubeconfig`) → all
  provisioning + teardown on ai-trust-1.

### Remaining to go live (deploy)
1. CRD `subscriptions.sub.aitrust.remote` on prod (local mirror target for the sync-agent).
2. `federation-operator` Deployment in prod ns `aitrust-remote` — in-cluster SA + ClusterRole on
   `sub.aitrust.remote` subscriptions(+/status), mounts the a1 kubeconfig Secret at `/etc/a1/kubeconfig`,
   env pointing PROVIDER_NS/domainSuffix/gateway/Keycloak at **ai-trust-1**.
3. `api-syncagent` Deployment bound to prod kcp ws `root:providers:ai-trust-remote` / `sub.aitrust.remote`
   (+ hostAlias fix) — publishes the `subscriptions` resource so the Stage-2 tile becomes enable-able.
4. Stage 4 brokering folded into the reconcile (ensure `fed-<org>` realm on a1 + OIDC IdP → prod realm).

