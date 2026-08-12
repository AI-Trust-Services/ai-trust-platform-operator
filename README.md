# AI Trust Platform as an MSP Provider on `ai-trust-1`

Publishes the **AI Trust Platform** app (from `../ai-trust-platform-main`, deployed standalone in
`../Standard_Ai_Platform`) as a **Platform Mesh MSP provider** — the same pattern as the apeirora
private-llm / chat-ui showroom providers. A customer sees a tile in the portal, clicks **Enable**, and
gets **their own isolated instance** of the whole platform.

- **Instance model:** FULL APP COPY per Enable. The operator stamps the entire ~23-service stack
  (6 domains × backend+frontend, workers, oauth2-proxy/shell) **plus dedicated backing stores**
  (postgres / clickhouse / minio / rabbitmq / keycloak) into a **fresh namespace** per instance.
- **Isolation:** one full copy per namespace. The app stays single-tenant — **no app code changes**.
  Every in-cluster reference uses short service DNS (`postgres`, `keycloak`, …) that resolves
  within-namespace, so swapping the namespace string IS the isolation.
- **Runs on the stock Platform Mesh already installed on `ai-trust-1`** (`../Standard_Platform_Mesh`).
  Hard rail: this bundle only targets `ai-trust-1`; never creates/deletes a shoot.

---

## How it works

Two Helm charts (like every mesh provider):

| Chart | Installed where | Contains |
|-------|-----------------|----------|
| **`charts/aitrust-msp-app`** (workload) | shoot ns `aitrust-msp` | the **operator** (watches `AITrustPlatformInstance`, stamps a full app copy per CR), the **api-syncagent** (mirrors the CR between the consumer's kcp workspace and the shoot), and the **portal nginx** serving `/pm-content.json` (marketplace tile) |
| **`charts/aitrust-pm-app`** (kcp) | workspace `root:providers:ai-trust` | **APIExport** `trust.aitrust.msp`, **ContentConfiguration** (points at the in-cluster nginx), **ProviderMetadata**, **apiexport-bind** RBAC |

The **operator** (`operator/`, Go, controller-runtime) is a port of `../Standard_Ai_Platform/scripts/3-deploy-app.sh`:
it **embeds** the gold app manifests (`config/k8s-app/`) via `embed.FS` and, per CR, renders them
(namespace swap + per-instance URL + fresh cookie secret + image registry/tag), node-pins the Jobs,
applies in order, patches keycloak/oauth2 to the instance host, wires one HTTPRoute, and aggregates
status across all workloads. A finalizer removes the routes + namespace on delete.

**Customer flow:** Account org → child Account → APIBinding (Enable) → create an `AITrustPlatformInstance`
→ syncagent mirrors it to a per-consumer namespace on the shoot → operator provisions the copy → status
+ URL flow back → open `https://<instance>.<mesh-domain>` and log in via that instance's own Keycloak.

---

## What happens behind the scenes when a customer clicks **Create** (does it make a new worker?)

**No — Create does NOT provision a new Gardener worker/node per instance.** Every instance shares the
existing **`msp-at-big`** pool (`m_c16_m128_v2`, 128 Gi). The operator pins all instance pods to it via
`nodeSelector: workload=msp-aitrust`. Isolation is **namespace-level** (one full app copy per namespace),
all landing on the shared pool.

```
Portal "Create"  (GraphQL mutation createAITrustPlatformInstance)
      │
      ▼
1. CR created:  AITrustPlatformInstance/<name>  in the customer's account workspace (kcp)
      │
      ▼
2. api-syncagent  mirrors the CR spec-down onto the shoot, into a per-consumer namespace
   named  aitp-<consumer-logical-cluster-id>-<name>   (e.g. aitp-33hins0iklcwfg45-d)
      │
      ▼
3. operator (watching the CR) reconciles:
     • creates that namespace
     • renders the embedded app manifests (swap namespace, per-instance URL, fresh cookie secret,
       image registry/tag)
     • applies ~40 objects: 6 backends + 6 frontends + workers + otel + shell + oauth2-proxy +
       dedicated postgres/clickhouse/minio/rabbitmq/keycloak + 4 init Jobs + Secrets/ConfigMaps
     • patches keycloak KC_HOSTNAME + oauth2-proxy args to the instance hostname
     • creates 1 HTTPRoute (+ a /keycloak bypass route) + ReferenceGrant on the shared mesh gateway
      │
      ▼
4. the kube-scheduler places those pods onto EXISTING msp-at-big node(s) (nodeSelector workload=msp-aitrust)
      │
      ▼
5. operator aggregates readiness across all ~23 Deployments; when all Available it flips the CR to
   status.phase=Ready / status.ready=true / status.url=https://<host>.  status flows back up to the portal.
      │
      ▼
6. finalizer on delete: removes the HTTPRoutes + deletes the namespace (cascades the whole copy).
```

**When does a node actually get added?** Only via the Gardener **cluster-autoscaler** if the `msp-at-big`
pool (min 1, **max 4**) runs out of CPU/memory as you add instances — driven by resource pressure, not by
the act of creating an instance. One 128 Gi node holds several instances (each ~8–10 Gi for `standard`;
use `sizeClass=small` to pack more). If you ever want **one dedicated node per instance** instead of
namespace isolation on a shared pool, that's a different design (a worker pool per instance) — not what
this bundle does.

---

## The CRD

```yaml
apiVersion: trust.aitrust.msp/v1alpha1
kind: AITrustPlatformInstance
metadata: { name: my-aitrust }
spec:
  displayName: "AI Trust — tenant"
  hostname: ""            # optional; derived <ns>-<name>.<suffix> if empty
  sizeClass: standard     # small | standard | large
  adminEmail: you@example.com
# status: { ready, url, phase, namespace, conditions[] }
```

## 3-step usage
1. **Garden login** (once, Ubuntu terminal): `bash prerequisites/login.sh`
2. **One-click deploy:**
   `MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash '/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/scripts/deploy.sh'`
   (~30–45 min: worker pool ~10 min + operator build/push + charts + one instance ~5–8 min)
3. **See the tile / open the instance** — step 7 prints the instance URL + the portal nav path
   (account → Namespaces → default → expand **"AI Trust Platform"**).

Reset (remove instances + provider, keep the mesh): `bash scripts/reset.sh` (`--pool` also drops the pool).

## Steps (`deploy.sh` runs 0→7)
| Step | Does |
|------|------|
| `0-check-prerequisites` | tools, garden reachable, mesh Ready, charts lint, docker login |
| `1-worker-pool` | dedicated **`msp-at-big`** pool (`m_c16_m128_v2`, 128 Gi, label `workload=msp-aitrust`); instances SHARE this pool (namespace isolation), autoscales up to max 4 nodes under pressure |
| `2-build-operator-image` | build + push `aitrust-msp-operator` (embeds the app manifests). App images are **reused**, not rebuilt |
| `3-provider` | provider ws + **PM chart first** + workload chart + syncagent hostAlias + bind_authenticated; waits APIExport publishes `aitrustplatforminstances` |
| `4-consumer-workspace` | org + child Account (SAR-poll + Store-wait + webhook-roll, ported from the MSP demo) |
| `5-bind-apis` | APIBinding to `trust.aitrust.msp` (claims secrets/namespaces/events) — the scripted "Enable" |
| `6-create-instance` | create one `AITrustPlatformInstance` in the account |
| `7-verify-portal` | `/pm-content.json` 200 + ContentConfiguration Ready + instance `status.ready`; prints URL + nav |

## Requirements
- The stock mesh on `ai-trust-1` (from `../Standard_Platform_Mesh`), Ready.
- The app images on `mirceacraciun795:aitrust-1` (from `../Standard_Ai_Platform` step 2) — reused as-is.
- `prerequisites/`: `garden-kubeconfig.yaml`, `login.sh`, `tls.*`. WSL tools: kubectl, helm, jq, docker, python3.

## Files
```
Standard_AiTrust_MSP/
├── README.md · msp_aitrust_howto.md · CLAUDE_AUTH.md · DEPLOYMENT_RECORD.md
├── prerequisites/ config.env · garden-kubeconfig.yaml · login.sh · tls.*
├── operator/       main.go · go.mod · Dockerfile · manifests/ (embedded app manifests)
├── charts/aitrust-msp-app/  (workload: CRD, operator, syncagent, portal nginx)
├── charts/aitrust-pm-app/   (kcp: APIExport, ContentConfiguration, ProviderMetadata, RBAC)
├── config/k8s-app/  (the gold app manifests — source of truth, copied into the operator at build)
├── config/ingress/  (gateway-listener + httproute templates, for reference)
└── scripts/ lib.sh · deploy.sh · 0-check … 7-verify-portal · reset.sh
```

## Reused mesh fixes (baked in — from `../Standard_MSP_Demo`)
- `KCP_INCLUSTER_URL` on **:8443** (chart default :6443 is wrong here).
- **PM chart before workload chart** (syncagent needs the APIExportEndpointSlice at startup).
- **syncagent hostAlias** `root.kcp.localhost → frontproxy ClusterIP`.
- **bind_authenticated** (`apiexport-bind → system:authenticated`) so a portal user can Enable.
- **ContentConfiguration → in-cluster HTTP Service** (self-signed mesh breaks external-HTTPS CC TLS verify).
- Tiles are **namespace-scoped** — they render at account → namespace, not the account dashboard.
