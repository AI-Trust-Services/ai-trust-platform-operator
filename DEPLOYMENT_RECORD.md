# DEPLOYMENT RECORD — AI Trust MSP provider on `ai-trust-1`

Live actuals from publishing the AI Trust Platform as an MSP provider. (Filled during the live run;
update as steps complete.)

## CRITICAL: instance login redirect loop — fix must be in the MANIFEST, not a post-apply patch
The per-instance app bounced on login (Keycloak -> oauth2 -> Keycloak, never showing the form). Two causes,
both being REVERTED by the operator's server-side apply because they were applied as post-apply
`kubectl patch`es that lose the race against the next reconcile's manifest apply:
1. oauth2-proxy `--cookie-secure=false` on an HTTPS instance -> browser never returns the session cookie ->
   infinite redirect. Must be `true`.
2. oauth2-proxy issuer/redeem/jwks/logout URLs lacked the `/keycloak` prefix (`http://keycloak:8080/realms/...`)
   while Keycloak serves under `KC_HTTP_RELATIVE_PATH=/keycloak` -> token/jwks 404 -> login never completes.
FIX: bake the correct values into the EMBEDDED MANIFESTS (`operator/manifests/` AND source `config/k8s-app/`),
not operator patches: `40-workers-shell-proxy.yaml` -> oauth2 URLs `/keycloak/realms/...` + `--cookie-secure=true`;
`10-infra.yaml` -> keycloak `KC_HTTP_RELATIVE_PATH=/keycloak` + readiness `/keycloak/realms/master` + rabbitmq
`readinessProbe.timeoutSeconds: 5`. The per-host `--login-url`/`--redirect-url` stay as `$(KEYCLOAK_PUBLIC_URL)`/
`$(APP_PUBLIC_URL)` env refs (operator renders those per instance). Rebuild operator (v6); recreate any
pre-v6 instance. Verified live: instance `d` Ready, oauth2 cookie `secure(https):true`, URLs `/keycloak/realms`.
Login: admin / password (realm `ai-trust`).

## ⚠️ CRITICAL: pm-content resourceDefinition must use `apiGroup`/`entity`/`entityCollection` keys
The portal **Create** form failed with `V1alpha1undefined_Input` / `createundefined` even after the group
rename. **Real root cause (confirmed by extracting the create() fn from the portal's compiled
`platform-mesh-portal-ui-wc.js`):** this portal build's generic-list-view reads the resource descriptor
via keys **`apiGroup`, `version`, `entity`, `entityCollection`** — NOT `group`/`kind`/`plural`:
```js
create(t,i,o){ const {apiGroup:s, entity:l, version:h}=i; ... operation:`create${l}` ... }  // create<entity>
function Pz(n,e,t){...return `${i}${t}_Input`}  // input type from apiGroup+version+entity
function dm(n,e="_"){return [n.apiGroup,n.version,n.entity].filter(Boolean).join(e)}  // list field
```
We had written `group/kind/plural/singular`, so `entity`=undefined → `create`+undefined=`createundefined`
and only `version` survived → `V1alpha1undefined_Input`. **FIX: the pm-content
`context.resourceDefinition` MUST include `apiGroup`, `version`, `entity` (=Kind),
`entityCollection` (=plural Kind), `scope`.** (Baked into `charts/aitrust-msp-app/templates/portal-integration.yaml`.)
**AND `apiGroup` MUST be the UNDERSCORED form** (`trust_aitrust_msp`, not `trust.aitrust.msp`) — the portal
uses it verbatim as a GraphQL field name, so dots cause `Syntax Error: Unexpected character "."`.
NOTE the hyphen theory was WRONG — group hyphen is irrelevant; the key names were the bug. The content
nginx bakes pm-content.json at pod start → after changes: `kubectl -n aitrust-msp rollout restart deploy/aitrust-portal-integration`.

## ⚠️ CRITICAL: API group must NOT contain a hyphen
The provider API group is **`trust.aitrust.msp`** — originally `trust.ai-trust.msp` (with a hyphen in the
middle segment). The hyphen caused the portal **Create** form to fail with:
`Variable "$object" cannot be non-input type "V1alpha1undefined_Input!" … Cannot query field "v1alpha1"
on type "Mutation"` — the portal emitted `v1alpha1 { createundefined(object: V1alpha1undefined_Input) }`.
The kcp gateway tolerated the hyphen for **queries** (so the list view + tiles worked), but the portal's
**create-mutation** builder could not derive the Kind from a hyphenated group → `undefined`. Every working
showroom provider uses a hyphen-free middle segment (`llm.privatellms.msp`, `ui.privatellms.msp`).
**Fix: keep the group hyphen-free.** After renaming, republishing (APIExport `trust.aitrust.msp`, schema
`vbd3d9af8…`), and restarting the content nginx (baked pm-content.json), a 5-check workflow confirmed:
schema clean · API create works · gateway builds a valid type (0 `undefined`) · binding Bound · served
content advertises `trust.aitrust.msp`. NOTE: the content nginx bakes pm-content.json at pod start — after
any content/group change, `kubectl -n aitrust-msp rollout restart deploy/aitrust-portal-integration`.

## Target
- Shoot **`ai-trust-1`** (project `garden-ai-trust`), stock Platform Mesh from `../Standard_Platform_Mesh`.
- Mesh domain / instance suffix: `aitrust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`.

## Artifacts
- Operator image: `mirceacraciun795/aitrust-msp-operator:v1` — **built + pushed** (embeds the app manifests).
- App images: reused `mirceacraciun795/aitrust-<svc>:aitrust-1` (from `../Standard_Ai_Platform`) — not rebuilt.
- Provider workspace: `root:providers:ai-trust`; APIExport `trust.ai-trust.msp`.
- Workload ns on the shoot: `aitrust-msp` (operator + syncagent + portal nginx).
- Worker pool: `msp-aitrust` (`g_c8_m16_v2`, `eu-de-1b`, label `workload=msp-aitrust`) — **Gardener pool
  names are max 15 bytes** (the initial `worker-msp-aitrust` was rejected → shortened).

## CRD
`AITrustPlatformInstance` (group `trust.ai-trust.msp`, v1alpha1, Namespaced). Spec: displayName, hostname?,
sizeClass, adminEmail, registry/tag overrides. Status: ready, url, phase, namespace, conditions.

## Step results (live)
| Step | Result |
|------|--------|
| 0 check | PASS — tools, garden, mesh Ready, charts lint, docker OK |
| 1 worker-pool | pool `msp-aitrust` added (after 15-byte rename); node Ready |
| 2 operator image | `aitrust-msp-operator:v1` pushed |
| 3 provider | **PASS** — provider ws + PM chart + workload chart + hostAlias + bind_authenticated; APIExport publishes `aitrustplatforminstances` |
| 4 consumer-ws | _running_ |
| 5 bind | _running_ |
| 6 instance | _pending_ |
| 7 verify | _pending_ |

## Live fixes discovered during step 3 (all baked into the charts/scripts)
These are the "next time" notes — each was a real failure hit + fixed on 2026-08-11:
1. **APIExport apiVersion** must be `apis.kcp.io/**v1alpha2**` (metadata-only; the syncagent owns spec).
   v1alpha1 → helm install failed.
2. **Helm into a kcp workspace needs `--namespace <ns> --create-namespace`** — a provider workspace has
   no `default` namespace for Helm's release Secret → `create: failed to create: namespaces "default"
   not found`. (Added `--namespace aitrust --create-namespace` to the pm install.)
3. **api-syncagent image tag** = `ghcr.io/kcp-dev/api-syncagent:**v0.5.1**` (my `0.3.0` → ImagePullBackOff).
4. **syncagent args** must match the real binary: `--namespace=$(POD_NAMESPACE) --enable-leader-election=true
   --apiexportendpointslice-ref=<export> --agent-name=… --kcp-kubeconfig=/etc/api-syncagent/kcp/kubeconfig
   --published-resource-selector=app.kubernetes.io/name=aitrust-syncagent`. Missing/empty
   `--apiexportendpointslice-ref` → "required" crash (the value comes from `exportName`, which I had to
   ALSO add to the WORKLOAD chart values, not just the pm chart).
5. **syncagent ClusterRole** needs `apiextensions.k8s.io/customresourcedefinitions` (get/list/watch) to
   read the local CRD, AND `syncagent.kcp.io/publishedresources` **+ `/status`** with patch (to write the
   generated APIResourceSchema name back). Missing either → APIExport never populates `spec.resources`.

Result: APIResourceSchema `v3e8f1826.aitrustplatforminstances.trust.ai-trust.msp` generated; APIExport
`spec.resources = [aitrustplatforminstances]`; syncagent holds the leader lease, clean logs.

## Live fixes discovered during steps 4–7 + instance provisioning
6. **VW-endpoint TLS**: the syncagent's sync controller dials the APIExport virtual-workspace at
   `https://root.kcp.localhost:8443/...` but the mesh cert is for `frontproxy/kcp.api.<domain>` → x509
   verify fails. Fix: strip CA + tls-server-name and set `insecure-skip-tls-verify: true` on the
   syncagent's embedded kcp kubeconfig (client cert still authenticates). Baked into step 3's python
   rewrite. (hostAlias alone only fixes DNS, not TLS SNI.)
7. **operator namespace name**: the Namespace object's `metadata.name: ai-trust-app` isn't matched by a
   `namespace:`-key replace → operator must replace the **bare token** `ai-trust-app` globally (operator v2).
8. **operator namespaces RBAC**: server-side apply of a Namespace needs `update, patch` (not just
   create) → added.
9. **status update conflict**: writing status twice per reconcile (mid + end) bumps resourceVersion and
   the terminal write conflicts → write status ONCE, and refetch-before-write in setPhase (operator v3).
   THIS was what kept phase stuck at Provisioning after all pods were Ready.
10. **domain typo**: `INSTANCE_DOMAIN_SUFFIX` was `aitrust-1...` (no hyphen) → instance host fell outside
    the mesh wildcard `*.ai-trust-1...` → unreachable (`http=000`). Fixed to `ai-trust-1...`; reuse the
    existing `terminate-wildstar` listener instead of creating our own (operator v4, env WILDCARD_LISTENER).
    After fix the instance URL routes through the gateway (`http=403` = oauth2-proxy login redirect).
11. **rabbitmq readiness probe** (`rabbitmq-diagnostics ping` timeout 1s) false-negatives on a busy node →
    bump timeout to 5s (broker is actually healthy; clients connect fine).
12. **footprint / node capacity**: a `standard` instance ≈ 8–10 Gi; stamping onto a `g_c8_m16_v2` (16Gi)
    left no headroom → under redeploy churn the node went NotReady + keycloak crash-looped (cascade).
    **Fix: use `m_c16_m128_v2` (16 vCPU / 128 Gi)** for the MSP pool — a full instance fits with room to
    spare. (Gardener machine name must match the cloudprofile exactly.)

## First successful run (operator v3, before the domain fix)
All 23 workloads Ready, 4 init Jobs Complete, CR `phase=Ready ready=true`, ContentConfiguration
`aitrust-ui` Ready, `/pm-content.json` served 200 — the full Enable→instance→tile flow proven. The v4
rebuild (domain fix) + move to the 128Gi node is to make the instance externally reachable + stable.

## FINAL live state (verified) — operator v4 on the 128Gi node
- Worker pool: **`msp-at-big`** (`m_c16_m128_v2`, 16 vCPU / 128 Gi). The old `g_c8_m16_v2` `msp-aitrust`
  pool was **removed** (undeployed) — a full instance ran the node out of headroom + caused a keycloak
  crash-cascade; the 128Gi node fixed it. Bundle now defaults `WORKER_TYPE=m_c16_m128_v2`.
- Instance `my-aitrust` in consumer ws `root:orgs:aitrustdemo:tenant`: **`phase=Ready ready=true`**,
  all 23 deployments Ready, all pods on the `msp-at-big` node.
- URL `https://q3c0weh7suf5hgjk-my-aitrust.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`
  routes through the mesh gateway (`http=403` → oauth2-proxy Keycloak login; a browser logs in).
- ContentConfiguration `aitrust-ui` Ready; portal tile renders (account → Namespaces → default →
  "AI Trust Platform"). Operator image `mirceacraciun795/aitrust-msp-operator:v4`.
- **Whole flow works end-to-end**: portal Enable (APIBinding) → create AITrustPlatformInstance →
  syncagent mirrors it → operator stamps a full isolated app copy → status+URL flow back.

## Fixes applied (baked into the bundle)
1. `KCP_INCLUSTER_URL` on `:8443`.
2. PM chart before workload chart.
3. syncagent hostAlias `root.kcp.localhost → frontproxy ClusterIP`.
4. `bind_authenticated` (+ pm chart binds `system:authenticated`) for portal Enable.
5. ContentConfiguration → in-cluster HTTP nginx (`http://aitrust-portal.aitrust-msp.svc.cluster.local/pm-content.json`).
6. Worker pool name ≤ 15 bytes (Gardener constraint).
7. Operator cluster-scoped RBAC (creates namespaces, applies the app stack anywhere, patches the gateway).

## Notes
- Each instance ≈ 8–10 Gi RAM + 25 Gi storage → roughly one standard instance per `g_c8_m16_v2` node.
- Tiles are namespace-scoped: account → Namespaces → default → expand "AI Trust Platform".
