# AI Trust Platform **MT** (Multi-Tenant) as an MSP Provider on `ai-trust-1`

**Version:** 4 (tag `v0.4`) · **Status:** multi-tenant MSP variant is the content of `main`.
See [`CHANGELOG.md`](CHANGELOG.md) for what changed; the version string lives in [`VERSION`](VERSION).

Publishes the **AI Trust Platform** app (multi-tenant Stage-A build from `../ai-trust-platform-main`) as a
**Platform Mesh MSP provider** — the same pattern as the apeirora private-llm / chat-ui showroom providers.
A customer sees a tile in the portal, clicks **Enable**, and creates a **Subscription** — and gets an
**isolated tenant** inside **one shared platform**, not a private copy.

- **Subscription model:** ONE shared app is deployed **once** (`3b-shared-app.sh`). Each Enable creates a
  **`Subscription`** CR; the operator provisions a **tenant** — a per-tenant Keycloak realm whose tokens
  carry `tenant_id` — inside that shared app. It does **NOT** stamp a ~23-service app copy per customer.
- **Isolation:** `tenant_id` + Postgres **RLS** + per-tenant ClickHouse/MinIO scoping, all enforced inside
  the shared app (Stage A). The auth boundary is the per-tenant realm; the data boundary is `tenant_id`.
- **Fully isolated from the existing `../Standard_AiTrust_MSP` (full-copy) provider** — different API group
  (`sub.aitrustmt.msp`), workspace (`root:providers:ai-trust-mt`), namespace (`aitrust-mt-msp`), worker pool
  (`ai-trust-mt`), and image tag (`aitrust-mt`). The two providers never collide.
- **Runs on the stock Platform Mesh already installed on `ai-trust-1`** (`../Standard_Platform_Mesh`).
  Hard rail: this bundle only targets `ai-trust-1`; never creates/deletes a shoot.

---

## How it works

Two Helm charts (like every mesh provider) + the shared app + a subscription operator:

| Chart / component | Installed where | Contains |
|-------------------|-----------------|----------|
| **`charts/aitrust-mt-app`** (workload) | shoot ns `aitrust-mt-msp` | the **MT operator** (watches `Subscription`, provisions a per-tenant realm), the **api-syncagent** (mirrors the CR between the consumer's kcp workspace and the shoot), and the **portal nginx** serving `/pm-content.json` |
| **`charts/aitrust-mt-pm-app`** (kcp) | workspace `root:providers:ai-trust-mt` | **APIExport** `sub.aitrustmt.msp`, **ContentConfiguration**, **ProviderMetadata**, **apiexport-bind** RBAC |
| **shared app** (`3b-shared-app.sh`) | shoot ns `aitrust-mt-msp` | the ONE multi-tenant AI Trust stack (`TENANCY_MODE=jwt`, RLS app role), reached at `SHARED_APP_HOST`; all tenants share it |

The **MT operator** (`operator/`, Go, controller-runtime) embeds **only** `manifests/*.tmpl` (the
tenant-provision Job template) via `embed.FS`. Per `Subscription` it derives the tenant id from the mesh
account, stamps a one-shot Job that runs the app's Keycloak provisioner against the **shared** Keycloak to
create a per-tenant realm (`t-<tenantId>`), and writes the tenant's login URL + realm + tenantId back to
status. The finalizer soft-disables the tenant (the append-only inference log is never deleted).

**Customer flow:** Account org → child Account → APIBinding (Enable) → create a `Subscription` →
syncagent mirrors it to a per-consumer namespace on the shoot → operator provisions the tenant realm in the
shared app → status + tenant URL flow back → open the tenant URL and log in via that tenant's own realm.

---

## Does clicking **Create** make a new worker or a new app copy?

**No to both.** There is exactly **one** app deployment. Create only adds a **tenant realm** to the shared
Keycloak and flips the `Subscription` to Ready — no new namespace, no new stack, no new node. All tenants
run on the shared app pinned to the single **`ai-trust-mt`** pool (`m_c16_m128_v2`, 128 Gi). The Gardener
cluster-autoscaler only adds a node if the shared app's own load exceeds one node (min 1, max 4).

```
Portal "Create"  (GraphQL mutation createSubscription)
      │
      ▼
1. CR created:  Subscription/<name>  in the customer's account workspace (kcp)
      │
      ▼
2. api-syncagent mirrors the CR spec-down onto the shoot, into a per-consumer namespace
   named after the consumer's kcp logical-cluster id (== the tenant id)
      │
      ▼
3. MT operator (watching the CR) reconciles:
     • tenantId = cr.Namespace (the consumer cluster id);  realm = t-<tenantId>
     • stamps a one-shot tenant-provision Job (PROVISION_IMAGE = aitrust-keycloak-provision:aitrust-mt)
       that creates the per-tenant realm in the SHARED Keycloak (tokens carry tenant_id)
     • writes status.url / status.realm / status.tenantId back (mirrored up to the portal)
      │
      ▼
4. tenant logs into the shared app at its URL; the app enforces tenant_id via RLS + scoped ClickHouse/MinIO.
      │
      ▼
5. finalizer on delete: soft-disables the tenant (drops the provisioning Job; DATA retained).
```

---

## The CRD

```yaml
apiVersion: sub.aitrustmt.msp/v1alpha1
kind: Subscription
metadata: { name: my-subscription }
spec:
  displayName: "AI Trust MT — tenant"
  plan: standard          # standard | enterprise  (cosmetic tier label; no per-tenant infra)
  adminEmail: you@example.com
# status: { ready, url, tenantId, realm, phase, observedGeneration, conditions[] }
```

No `hostname` / `sizeClass` — a subscription provisions no per-tenant infrastructure, so there is nothing
to size, and the tenant URL is derived (`<tenantId>-<name>.<shared-suffix>`, routes to the shared host).

## 3-step usage
1. **Garden login** (once, Ubuntu terminal): `bash prerequisites/login.sh`
2. **One-click deploy:**
   `MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash '/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP/scripts/deploy.sh'`
   (worker pool ~10 min + operator/app image build+push + charts + shared app + one subscription ~1-2 min)
3. **See the tile / open the tenant** — step 7 prints the shared app host, the tenant URL + realm, and the
   portal nav path (account → Namespaces → default → expand **"AI Trust Platform MT"**).

Reset (remove subscriptions + shared app + provider, keep the mesh): `bash scripts/reset.sh`
(`--pool` also drops the `ai-trust-mt` pool).

## Steps (`deploy.sh` runs 0 → 1 → 2 → 2b → 3 → 3b → 4 → 5 → 6 → 7)
| Step | Does |
|------|------|
| `0-check-prerequisites` | tools, garden reachable, mesh Ready, charts lint, docker login |
| `1-worker-pool` | dedicated **`ai-trust-mt`** pool (`m_c16_m128_v2`, 128 Gi, label `workload=ai-trust-mt`); the shared app + operator run here |
| `2-build-operator-image` | build + push `aitrust-mt-operator:v1` (embeds only `manifests/*.tmpl`) |
| `2b-build-app-images` | build + push the **MT app images** from `../ai-trust-platform-main` at tag **`aitrust-mt`** (incl. `aitrust-keycloak-provision`, the operator's PROVISION_IMAGE) |
| `3-provider` | provider ws + **PM chart first** + workload chart + syncagent hostAlias + bind_authenticated; waits APIExport publishes `subscriptions` |
| `3b-shared-app` | deploy the **ONE shared MT app** (`TENANCY_MODE=jwt`, RLS app role) at `SHARED_APP_HOST`, pinned to `ai-trust-mt` |
| `4-consumer-workspace` | org + child Account (SAR-poll + Store-wait + webhook-roll, ported from the MSP demo) |
| `5-bind-apis` | APIBinding to `sub.aitrustmt.msp` (claims secrets/namespaces/events) — the scripted "Enable" |
| `6-create-subscription` | create one `Subscription` in the account |
| `7-verify-portal` | `/pm-content.json` 200 + ContentConfiguration Ready + `Subscription status.ready`; prints tenant URL + realm |

## Requirements
- The stock mesh on `ai-trust-1` (from `../Standard_Platform_Mesh`), Ready.
- The Stage-A multi-tenant app source at `../ai-trust-platform-main` (step 2b builds the `aitrust-mt` images).
- `prerequisites/`: `config.env` (source of truth), `garden-kubeconfig.yaml`, `login.sh`, `tls.*`.
  WSL tools: kubectl, helm, jq, docker, python3.

## Files
```
Standard_AiTrust_MT_MSP/
├── README.md · msp_aitrust_mt_howto.md
├── prerequisites/ config.env · garden-kubeconfig.yaml · login.sh · tls.*
├── operator/       main.go · go.mod · Dockerfile · manifests/ (tenant-provision-job.tmpl only)
├── charts/aitrust-mt-app/     (workload: Subscription CRD, operator, syncagent, portal nginx)
├── charts/aitrust-mt-pm-app/  (kcp: APIExport, ContentConfiguration, ProviderMetadata, RBAC)
├── config/k8s-app/   (the gold app manifests — rendered by 3b for the shared app)
├── config/shared-app/  (MT overlay: pg-init RLS role + secret-config TENANCY_MODE=jwt)
├── config/ingress/   (gateway-listener + httproute templates, for reference)
└── scripts/ lib.sh · deploy.sh · 0-check … 2b-build-app-images · 3b-shared-app · 6-create-subscription · 7-verify-portal · reset.sh
```

## Reused mesh fixes (baked in — from `../Standard_MSP_Demo`)
- `KCP_INCLUSTER_URL` on **:8443** (chart default :6443 is wrong here).
- **PM chart before workload chart** (syncagent needs the APIExportEndpointSlice at startup).
- **syncagent hostAlias** `root.kcp.localhost → frontproxy ClusterIP`.
- **bind_authenticated** (`apiexport-bind → system:authenticated`) so a portal user can Enable.
- **ContentConfiguration → in-cluster HTTP Service** (self-signed mesh breaks external-HTTPS CC TLS verify).
- Tiles are **namespace-scoped** — they render at account → namespace, not the account dashboard.

## Deploy behavior
- **`imagePullPolicy: Always`** on all app / job / worker containers (and the operator) — deploys always
  pull the latest build under the current image tag (`aitrust-mt`), so a rebuild pushed under the same tag
  is picked up on the next pod start rather than serving a node-cached layer.
