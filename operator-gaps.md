# Operator install gaps — `ai-trust-platform-operator`

Findings from preparing a fresh install of `github.com/AI-Trust-Services/ai-trust-platform-operator`
(v0.9.0) to deploy the AI Trust Platform as a Platform-Mesh MSP provider ("AI Trust Platform Market")
on the Gardener shoot `ai-trust-1`. Each gap: **symptom → root cause (file:line) → fix**. These are the
things that are NOT self-contained/automated and will block or surprise a clean install.

Deploy pipeline for reference (`scripts/deploy.sh`): `0-check-prerequisites → 1-worker-pool →
2-build-operator-image → 2b-build-app-images → 3-provider → 3b-shared-app → 4-consumer-workspace →
5-bind-apis → 6-create-subscription → 7-verify-portal`.

---

## GAP 1 — `config/k8s-app/` is missing from the repo (hard blocker)

**Symptom:** `3b-shared-app.sh` aborts under `set -euo pipefail` at the first `render` — the "gold" app
manifests it reads do not exist.

**Root cause:** `scripts/3b-shared-app.sh:13` sets `GOLD="$BUNDLE/config/k8s-app"` and
`:61-69` render `$GOLD/{00-namespace,01-cm-ch-config,01-cm-otelcol,10-infra,20-jobs,30-app,
40-workers-shell-proxy}.yaml`. The repo's `config/` contains only `ingress/` and `shared-app/` —
**`config/k8s-app/` is absent.** (`config/shared-app/` has just `01-cm-pg-init-mt.yaml` +
`02-secret-config-mt.tmpl`, not the 9 gold files.)

**Fix:** the 9 gold manifests exist in the source bundle
`Standard_AiTrust_MT_MSP/config/k8s-app/` (`00-namespace.yaml`, `01-cm-ch-config.yaml`,
`01-cm-otelcol.yaml`, `01-cm-pg-init.yaml`, `02-secret-config.tmpl`, `10-infra.yaml`, `20-jobs.yaml`,
`30-app.yaml`, `40-workers-shell-proxy.yaml`). Copy them into the operator repo's `config/k8s-app/` and
commit, so the repo is self-installing. **The public repo cannot deploy the shared app without this.**

---

## GAP 2 — `config.env` is unfilled and there is no `.example`

**Symptom:** deploy dies early — `lib.sh` fails without `SHOOT_NAME`; hosts/domains render empty.

**Root cause:** `scripts/prerequisites/config.env` ships with the cluster-specific values **empty**:
`SHOOT_NAME`, `PROJECT`, `GARDENER_API`, `INSTANCE_DOMAIN_SUFFIX`, `SHARED_APP_HOST`, `OPS_HOST`.
`README.md:49` instructs `cp prerequisites/config.env.example prerequisites/config.env`, but **no
`.example` exists** and the path is wrong (actual: `scripts/prerequisites/config.env`, edited in place).
`install.sh:45-46` gives the correct path; the README does not.

**Fix:** ship a `scripts/prerequisites/config.env.example` with documented placeholders and fix the
README path. For ai-trust-1: `SHOOT_NAME=ai-trust-1`, `PROJECT=garden-ai-trust`,
`GARDENER_API=https://api.garden.gardener.cc-one.showroom.apeirora.eu`,
`INSTANCE_DOMAIN_SUFFIX=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`. Set
`APP_GIT_REF_DEFAULT` to the app branch you want to serve.

---

## GAP 3 — cluster cannot pull the images (no imagePullSecret)

**Symptom:** after 2/2b push images to `ghcr.io/ai-trust-services/*`, pods `ImagePullBackOff` if the
GHCR packages are private.

**Root cause:** steps `2-build-operator-image.sh` / `2b-build-app-images.sh` `docker push` to GHCR, but
**no imagePullSecret is created by any chart or script** (grep of `charts/` finds none). The charts set
`pullPolicy: Always` (`aitrust-app/values.yaml`) with no `imagePullSecrets`.

**Fix:** either make the GHCR packages public, or create a `dockerconfigjson` pull secret in
`aitrust-msp` (and reference it via the SA / `imagePullSecrets` in the operator + app deployments). The
tool should create this from the same GHCR creds it pushes with.

---

## GAP 4 — operator image tag drift (config.env v21 vs chart v22)

**Symptom:** confusion about which operator image runs; a stale/absent tag → ImagePull error.

**Root cause:** `config.env OPERATOR_TAG="v21"` but `charts/aitrust-app/values.yaml tag: v22`.
`3-provider.sh` overrides the chart with `--set operator.image.tag=$OPERATOR_TAG` (=v21), so **v21 wins
at deploy** — and step 2 must actually build+push v21. If someone skips step 2 expecting v22, nothing
matches.

**Fix:** align the two (bump `config.env` to the chart default, or vice-versa) and document that step 2
builds the tag `config.env` names.

---

## GAP 5 — `OPENFGA_STORE_ID` fail-fast depends on 3b completing

**Symptom:** operator crash-loops on startup (`mustEnv("OPENFGA_STORE_ID")`).

**Root cause:** `operator/config.go` fail-fasts on `OPENFGA_STORE_ID`; it is resolved and injected only
by `3b-shared-app.sh` (after the openfga-provision job) via `kubectl set env`. `values.yaml
openfgaStoreId: ""` and `3-provider.sh` do not set it. So if 3b fails (see GAP 1) the operator never
gets a valid store id.

**Fix:** none needed once GAP 1 is fixed and 3b runs; documented here because it makes GAP 1's failure
mode look like an operator bug when it is a missing-manifest cascade.

---

## GAP 6 — federated mode "prompts" don't exist

**Symptom:** `install.sh --mode federated` → operator crashes needing `REMOTE_KUBECONFIG`.

**Root cause:** `README.md:136-146` implies federated mode is interactive, but `install.sh` /
`deploy.sh` contain **no prompting code**; `operator/config.go` fail-fasts on `REMOTE_KUBECONFIG`
(+ `CENTRAL_KUBECONFIG`/`PAYLOAD_KUBECONFIG`/`PAYLOAD_CLUSTER_NAME`). They must be exported as env vars.

**Fix:** document the required env vars for federated mode, or add the prompts.

---

## GAP 7 — implicit prerequisites (mesh, KCP, DNS/TLS, app-repo access)

Not bugs, but the install **assumes** and only *checks* (never provisions):

- **Platform Mesh + KCP already Ready** on the shoot — `0-check-prerequisites.sh:12-17` checks
  `deploy portal` in `platform-mesh-system` and `KCP_INCLUSTER_URL` on `:8443`. If the mesh is down,
  install aborts. (Provisioning it is a separate bundle: `Standard_Platform_Mesh`.)
- **Wildcard DNS + gateway listener/cert** for `INSTANCE_DOMAIN_SUFFIX` / `SHARED_APP_HOST` /
  per-tenant `ai-trust-<org>.<suffix>` — must exist on the shoot; not created here.
- **App-repo read access** — `2b-build-app-images.sh:26` clones
  `github.com/AI-Trust-Services/ai-trust-platform` at `APP_GIT_REF`; the branch must contain
  `libs/authorization` (2b dies otherwise).
- **A mesh Keycloak realm named `<org>`** must exist before local-mode reconcile
  (`operator/reconciler.go:153-158` fails closed).

**Fix:** enumerate these prerequisites in the README's "Before you install" and have
`0-check-prerequisites.sh` verify DNS/gateway + app-repo reachability, not just the mesh portal.

---

## Summary — to make the repo cleanly installable

1. Commit `config/k8s-app/*` (GAP 1). 2. Add `config.env.example` + fix the README path (GAP 2).
3. Create/reference an imagePullSecret (GAP 3). 4. Align the operator tag (GAP 4).
5. Document federated env vars (GAP 6). 6. Expand the prerequisite checks + README (GAP 7).
GAP 5 resolves once GAP 1 is fixed.

---

## Marketplace component wiring (branch `marketplace`)

The operator's build list + gold manifests predate the platform's **Marketplace** component, so a
stock deploy produces the platform WITHOUT the Marketplace page. Branch `marketplace` adds it. What
changed (so it can be folded upstream / re-done for future app versions):

1. **`scripts/2b-build-app-images.sh`** — build + push three more images from the app repo:
   `aitrust/marketplace-backend` (`marketplace/backend/Dockerfile`, repo-root ctx),
   `aitrust/marketplace-frontend` (`marketplace/frontend`, `--build-arg VITE_MARKETPLACE_API_BASE=/api/marketplace/v1`),
   `aitrust/marketplace-health-worker` (`marketplace-health-worker/Dockerfile`, repo-root ctx). Pushed
   as `$REGISTRY/aitrust-marketplace-*:$TAG` to match the gold render.
2. **`config/k8s-app/10-infra.yaml`** — added the in-cluster **registry** (`registry:2` PVC+Deployment+
   Service on :5000) and the **marketplace** ServiceAccount + namespaced Role/RoleBinding
   (`marketplace-deployer`: manage Deployments/Services/Jobs/Secrets/Pods in-ns) — the in-cluster
   controller's RBAC.
3. **`config/k8s-app/30-app.yaml`** — added `marketplace-backend` (SA `marketplace`, :8009, `/health`
   probes, env in gold's explicit `app-secrets`/`app-config` style + `DEPLOY_TARGET=kubernetes`,
   `POD_NAMESPACE`, `MARKETPLACE_REGISTRY=registry:5000`, `MARKETPLACE_REGISTRY_SCHEME=http`,
   `OPENFGA_STORE_ID="__OPENFGA_STORE_ID__"`) + `marketplace-frontend` (:80). Images written as
   `aitrust/marketplace-*:kind` so `render()` rewrites them like every peer.
4. **`config/k8s-app/40-workers-shell-proxy.yaml`** — added `marketplace-health-worker` (mirrors
   policy-checker-worker; 3b's `worker` regex repoints its DB to `APP_DATABASE_URL`).
5. **Shell routes** — none needed: `.appsrc/shell/nginx.conf` already has `/marketplace/` +
   `/api/marketplace/`, and 2b rebuilds `aitrust/shell` from `.appsrc`, so the routes ship in the image.
6. **No new DB/provision job** — marketplace tables ride the existing `db-migrate`; `OPENFGA_STORE_ID`
   is injected post-provision by 3b (marketplace-backend matches its `backend` regex).

### LIVE-F — marketplace store-id / OpenFGA model
The marketplace backend reads `OPENFGA_STORE_ID` from env (not the `/config` PVC the app-repo Helm
mounts) — so the gold port drops that volume and adds the `OPENFGA_STORE_ID="__OPENFGA_STORE_ID__"` env
line. 3b seeds ONE shared app OpenFGA store; marketplace's own permission (`marketplace:manage`) must be
in that model. If the marketplace permission isn't in the seeded model, `require_permission` 403s — verify
the app-role model (openfga-provision from `mircea-marketplace`) includes the marketplace relations.

### LIVE-H — 3b is not idempotent for the one-shot Jobs (re-run fails)
**Symptom:** re-running `3b-shared-app.sh` fails: `Job.batch "db-migrate" is invalid: spec.template:
field is immutable` (same for clickhouse-migrate/keycloak-provision/minio-init).
**Root cause:** 3b `kubectl apply`s the Jobs in `20.yaml`; a completed Job's pod template is immutable,
so `apply` (a patch) is rejected on any re-run. `set -euo pipefail` then aborts the whole script.
**Fix:** `3b-shared-app.sh` should `kubectl delete job … --ignore-not-found` before applying `20.yaml`
(it already does this for `openfga-provision` at `:136` — extend to all four one-shot jobs). Workaround
used live: `kubectl -n <ns> delete job db-migrate clickhouse-migrate keycloak-provision minio-init` then
re-run 3b.

### LIVE-G — insecure in-cluster registry on Gardener (marketplace dockerfile/OCM builds only)
`registry:5000` is plain HTTP. Kind handles this via `containerdConfigPatches`
(`.appsrc/k8s/kind-config.yaml`), but the operator's Gardener worker pool (`1-worker-pool.sh:22`,
`cri: containerd`) sets **no** insecure-registry trust. **Impact is narrow:** the shared app + a
Marketplace registration of a **prebuilt (ghcr) image** are unaffected (they pull from GHCR); ONLY an
in-cluster **build** (kind="dockerfile"/OCM-build → push to registry:5000 → pull back) fails
(`http: server gave HTTP response to HTTPS client`). **Fix options (not done this pass):** (a) Shoot
`workers[].cri` registry-mirror / Gardener registry-cache; (b) TLS-fronted registry; (c) a DaemonSet
writing `/etc/containerd/certs.d/registry:5000/hosts.toml`. Documented as a known limitation.
