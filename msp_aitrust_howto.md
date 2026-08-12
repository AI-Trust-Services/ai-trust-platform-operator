# MSP-ifying the AI Trust Platform — how it's built

Audience: a developer who wants to understand how we turned the single-tenant AI Trust app into a
multi-tenant Platform Mesh provider without changing the app. Read alongside `README.md` and the
provider-pattern reference in `../Standard_MSP_Demo/msp_demo_howto.md`.

## 1. The idea in one paragraph
The app is a single-tenant monolith-of-microservices (23 workloads + 5 stateful stores, no `tenant_id`).
Instead of refactoring it for multi-tenancy, we give **each customer their own full copy** in an isolated
namespace. A tiny **operator** watches a CRD (`AITrustPlatformInstance`) and, per CR, renders + applies the
**exact same manifest set** the standalone bundle uses — just with the namespace, public URL, cookie
secret and image registry/tag substituted. Because every in-cluster reference uses short service DNS
(`postgres`, `keycloak`, …) that resolves within-namespace, the namespace swap is the entire isolation
mechanism. The api-syncagent + APIExport make the CRD bindable from a customer workspace (the portal
"Enable"), and a ContentConfiguration renders the marketplace tile.

## 2. Why an operator, and why it was cheap to build
`../Standard_Ai_Platform/scripts/3-deploy-app.sh` **already** parameterizes the whole deploy by
`APP_NS / APP_URL / APP_DOMAIN / COOKIE_SECRET` (its `render()` sed helper) and does the fiddly bits:
image rewrite `aitrust/<n>:kind → <registry>/aitrust-<n>:<tag>`, node-pinning the immutable Jobs BEFORE
apply, and the keycloak `KC_HOSTNAME` + oauth2-proxy args patches. The operator (`operator/main.go`) is a
near-line-for-line **Go port** of that script:
- **`embed.FS`** bakes `operator/manifests/*` (a copy of `config/k8s-app/`) into the image.
- `replacer()` = the sed transforms (namespace swap + `__APP_*__` placeholders + image rewrite).
- `applyJobs()` node-pins each Job podTemplate and sets `APP_URL` before apply (Jobs are immutable).
- `patchKeycloak()` / `patchOauth2()` = the exact post-apply patches from the script, per-instance URL.
- `wireIngress()` = the `4-ingress.sh` logic: ensure a wildcard listener, apply the app + keycloak-bypass
  HTTPRoutes + a ReferenceGrant.
- `aggregate()` rolls up all Deployments → a single `status.ready`; RequeueAfter 20s until settled.
- a **finalizer** deletes the routes + namespace on CR delete.

`step 2-build-operator-image.sh` re-syncs `operator/manifests ← config/k8s-app` so the embedded copy is
never stale. The **app images are reused** from `../Standard_Ai_Platform` — only the small operator is built.

## 3. The provider contract (identical to the showroom providers)
- **Workload chart** (`charts/aitrust-msp-app`) on the shoot: operator + api-syncagent (+ its kcp
  kubeconfig secret + a `PublishedResource` for the CR) + the portal nginx serving `/pm-content.json`.
- **PM chart** (`charts/aitrust-pm-app`) into `root:providers:ai-trust`: `APIExport trust.ai-trust.msp`,
  `ContentConfiguration` (points at the in-cluster nginx), `ProviderMetadata`, `apiexport-bind` RBAC.
- **PublishedResource** mirrors `AITrustPlatformInstance` spec-down into a per-consumer namespace
  (`naming.namespace = {{ .ClusterName }}`) and status-up. That per-consumer namespace on the shoot is
  where the operator sees the CR and provisions into `aitp-<consumer-ns>-<name>`.

## 4. Per-instance URL & auth
Each instance → `https://<instance>.<INSTANCE_DOMAIN_SUFFIX>` under a single wildcard listener
`terminate-aitrust-wild` (`*.<suffix>`) reusing the mesh `domain-certificate`. The operator creates two
HTTPRoutes per instance (app → oauth2-proxy:8080; `/keycloak` bypass → keycloak:8080) + a ReferenceGrant.
Keycloak + oauth2-proxy live IN the instance namespace, so `http://keycloak:8080` already targets the
right instance; the operator templates `KC_HOSTNAME` and all oauth2 URLs to the instance host — each copy
is self-consistent, no cross-tenant leakage. **Test login per instance** — this is the fiddliest area.

## 5. Placement / footprint
`worker-msp-aitrust` (`g_c8_m16_v2`, label `workload=msp-aitrust`). Each instance ≈ 8–10 Gi RAM + 25 Gi
storage, so roughly **one standard instance per node** — scale `WORKER_MAX`, or use `sizeClass=small` for
demos. The operator pins every instance pod + Job to this pool (same zone as the StatefulSets, else RWO
PVCs strand — the exact caveat from the standalone script).

## 6. Reused mesh fixes (see `../Standard_MSP_Demo`)
`KCP_INCLUSTER_URL :8443`; PM-chart-before-workload; syncagent `hostAlias root.kcp.localhost → frontproxy`;
`bind_authenticated`; ContentConfiguration → **in-cluster HTTP** (self-signed mesh breaks external-HTTPS CC
TLS verify); tiles are **namespace-scoped** (account → namespace → expand "AI Trust Platform", NOT the
dashboard — and open the portal ROOT then click through, don't paste a deep `/dashboard` URL which yields
a `:undefined` 403).

## 7. Troubleshooting
| Symptom | Cause / fix |
|---|---|
| syncagent `:6443 i/o timeout` | `KCP_INCLUSTER_URL` must be `:8443` (it is). |
| syncagent `root.kcp.localhost connection refused` | `patch_syncagent_hostalias` (step 3). |
| syncagent VW-endpoint `x509: valid for kcp.api… not root.kcp.localhost` | embedded kcp kubeconfig must have `insecure-skip-tls-verify: true` (CA+tls-server-name stripped) — step 3 python rewrite does this. |
| `no matches for kind AITrustPlatformInstance` in the account | APIExport hasn't published yet — step 3 waits; check the syncagent logs + the workload rollout. |
| Enable → `cannot create apibindings` | `bind_authenticated` (step 3) + the pm chart's `system:authenticated` binding; user must belong to the org. |
| Portal **Create** → `V1alpha1undefined_Input` / `createundefined` | pm-content `resourceDefinition` must use the keys THIS portal build reads: **`apiGroup`(underscored, e.g. `trust_aitrust_msp`) / `version` / `entity`(=Kind) / `entityCollection`(=plural Kind) / `scope`** — NOT `group`/`kind`/`plural`. Confirm against the running bundle: fetch `/assets/platform-mesh-portal-ui-wc.js` and grep `.entity`/`.apiGroup`/`.entityCollection`. Restart the content nginx after (it bakes pm-content at pod start). |
| Portal list → `Syntax Error: Unexpected character "."` | `apiGroup` must be the **underscored** form (`trust_aitrust_msp`) — the portal uses it verbatim as a GraphQL field name. |
| instance stuck `Provisioning` | app takes ~5–8 min; `kubectl -n aitp-<...> get pods`; check the migrate/keycloak-provision Jobs + rabbitmq (probe timeout must be ≥5s). |
| **instance login: redirect loop / no login form / blank page** | See §8. oauth2/keycloak URL + cookie fixes must be in the **manifest**, not operator patches (SSA reverts patches). AND browse the CORRECT host = the CR's `status.url` (`<consumer-cluster-id>-<name>.<suffix>`), NOT a shortened `<name>.<suffix>` — a hostname mismatch between the HTTPRoute, oauth2 `--redirect-url`, and the Keycloak client redirect URI causes 403. |
| tile not visible | see §6 — namespace-scoped + open portal root, not a pasted dashboard URL. |
| CC `x509 unknown authority` | CC must use the in-cluster HTTP svc URL (it does). |

## 8. Per-instance authentication — the full picture (learned the hard way)
Each instance is **self-contained**: its own Keycloak (realm `ai-trust`, served under `/keycloak` via
`KC_HTTP_RELATIVE_PATH`), its own oauth2-proxy, its own admin user (`admin`/`password` from the
keycloak-provision Job). It does NOT use the mesh/portal identity provider (that's Dex, only for the
portal itself). Login to an instance = that instance's Keycloak.

**Every value must agree on ONE hostname** — the CR's `status.url`, which is
`https://<consumer-logical-cluster-id>-<name>.<INSTANCE_DOMAIN_SUFFIX>` (e.g.
`25veqwflh7syq7fm-d.ai-trust-1...`). The pieces that must all match it:
- the HTTPRoute `hostnames` the operator creates on the gateway,
- oauth2-proxy `--redirect-url=<url>/oauth2/callback` and `--login-url=<url>/keycloak/…` (rendered from
  the `APP_PUBLIC_URL`/`KEYCLOAK_PUBLIC_URL` ConfigMap values),
- the Keycloak `oauth2-proxy` client's registered `redirectUris` (the provision Job sets this).
A mismatch (e.g. browsing a stale/shortened host, or a leftover HTTPRoute from a deleted instance
pointing at a gone namespace) → **403 / blank / redirect that never lands**. Always open the URL shown in
the portal's **URL column** (= `status.url`), and clean stale gateway HTTPRoutes when you delete/recreate.

**Auth config must live in the embedded manifests, not operator post-apply patches** — the operator
server-side-applies the manifest every reconcile, which REVERTS any `kubectl patch`. So bake into
`operator/manifests/` (+ source `config/k8s-app/`):
- `40-workers-shell-proxy.yaml` oauth2-proxy: issuer/redeem/jwks/logout URLs `/keycloak/realms/…`,
  `--cookie-secure=true`. Per-host `--login-url`/`--redirect-url` stay as `$(KEYCLOAK_PUBLIC_URL)`/
  `$(APP_PUBLIC_URL)` env refs (operator renders those per instance).
- `10-infra.yaml` keycloak: `KC_HTTP_RELATIVE_PATH=/keycloak`, readiness `/keycloak/realms/master`.
- rabbitmq readiness `timeoutSeconds: 5` (the default 1s false-negatives on a busy node → stuck Provisioning).
Rebuild the operator image after changing embedded manifests; recreate instances built by an older image.

**oauth2-proxy returns 403 (its Sign-In page) on `/` for an unauthenticated request — that is NORMAL**
(it renders a "Sign In" button page, HTTP 403 + HTML). The browser shows that page; you click through to
Keycloak. `/oauth2/start` → 302 to Keycloak confirms the flow works. A truly broken instance instead
returns **504** (gateway can't reach the backend — usually a stale route or wrong host) or a genuinely
blank body. Compare a known-good instance's `/` response (`<title>Frontend</title>` = app served vs
`<title>Sign In</title>` = oauth2 landing) to tell which state you're in. Internal `curl` to
`oauth2-proxy:8080` can mislead (no cookies) — test EXTERNALLY through the gateway with the real host.
