# Stage 1 — a1 credential for the prod federation controller  ✅ DONE

**Task #256.** Completed **2026-08-19**. Mechanism: **scoped ServiceAccount token on ai-trust-1**
(chosen over a re-minted 4h shoot-admin kubeconfig — durable, least-privilege, no refresher needed).

## What was created

**On ai-trust-1** (manifest: `stage1-a1-serviceaccount.yaml`) — NO control-plane / kcp change:
- `ServiceAccount aitrust-federation` in ns `aitrust-msp`.
- `Role/RoleBinding aitrust-federation` in `aitrust-msp` — least-privilege for tenant provisioning:
  - `batch/jobs`: get/list/watch/create/delete (stamp the tenant-stores Job).
  - `pods`, `pods/log`: get/list/watch (read Job progress).
  - `secrets`: **get/list only** (rendered Job references `app-secrets` via secretKeyRef; no create/delete).
  - `configmaps`: get/list/watch.
  - `apps/deployments`, `services`: full CRUD (per-tenant oauth2-proxy).
- `Role/RoleBinding aitrust-federation-routes` in ns `platform-mesh-system` — `gateway.networking.k8s.io/httproutes` CRUD only (publish `ai-trust-<org>.ai-trust-1` routes; existing per-tenant routes live there).
- `Secret aitrust-federation-token` (type `kubernetes.io/service-account-token`) — an explicitly-requested long-lived SA token (k8s 1.24+ doesn't auto-create these).

**On ai-trust-prod:**
- ns `aitrust-remote` created.
- `Secret aitrust-remote/aitrust-1-shoot-kubeconfig` — a kubeconfig built from the SA token + ai-trust-1
  API server + CA. This is what the Stage-3 federation controller mounts to reach ai-trust-1.

## Verification (live)

| Check | Result |
|---|---|
| create jobs -n aitrust-msp | ✅ yes |
| get secrets -n aitrust-msp | ✅ yes |
| create httproutes -n platform-mesh-system | ✅ yes |
| delete secrets -n aitrust-msp | ❌ no (least-privilege holds) |
| get nodes (cluster-scoped) | ❌ no |
| live: `get jobs -n aitrust-msp` via the SA kubeconfig | ✅ works |

## Refresh

**No periodic refresh needed.** A `kubernetes.io/service-account-token` Secret is long-lived and its
token is maintained by the cluster — unlike the Gardener shoot-admin kubeconfig (which expires in ~4h and
*would* have needed a re-minter). If the token is ever rotated/revoked, re-run
`stage1-a1-serviceaccount.yaml` + rebuild the prod Secret (`.stage1_apply.sh` is idempotent).

## a1 landscape confirmed (for later stages)
- Gateway `k8sapi-gateway` (traefik) in `platform-mesh-system`, address `130.214.18.166`.
- Per-tenant HTTPRoutes `aitrust-<org>` live in `platform-mesh-system`, host
  `ai-trust-<org>.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`.
- Existing a1 tenants: `fridaytest`, `martin`, `mircealast`, `sen` (+ `ops`). These must stay untouched.

## Files
- `stage1-a1-serviceaccount.yaml` — the SA + RBAC applied on ai-trust-1 (committed artifact).
