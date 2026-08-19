# Stage 2 — prod federated tile (kcp provider scaffolding)  ✅ DONE (scaffolding live)

**Task #257.** Completed **2026-08-19**. Applied live on **ai-trust-prod**. **Additive** — the existing
prod-local provider (`root:providers:ai-trust` / `sub.aitrust.msp`) is confirmed untouched.

## What was created (on prod)

**kcp (prod control plane):**
- Provider workspace **`root:providers:ai-trust-remote`** → phase **Ready**.
- **`APIExport sub.aitrust.remote`** — a bare shell (the sync-agent owns `spec.resources`; it publishes
  the `subscriptions` resource once the Stage-3 federation controller's sync-agent binds — see below).
- **`ProviderMetadata sub.aitrust.remote`** — displayName **"AI Trust Platform (on ai-trust-1)"**,
  description explains it is federated (workload on ai-trust-1, prod identity brokered).
- **`ContentConfiguration aitrust-ui`** — points the portal at the prod-side federated tile
  (`http://aitrust-remote-portal.aitrust-remote.svc.cluster.local/pm-content.json`).
- `ClusterRoleBinding apiexport-bind-authenticated` — `system:authenticated` can Enable.

**Shoot (prod workload) — ns `aitrust-remote`:**
- `ConfigMap aitrust-remote-tile` (from `stage2-remote-tile.json`) + `Deployment/Service
  aitrust-remote-portal` (nginx, 1/1) serving the federated `pm-content.json`. The tile's Subscription
  resource is group `sub.aitrust.remote`, category label **"AI Trust Platform (on ai-trust-1)"** (order
  811, just after the local tile's 810), with an extra `status.cluster` list column.

## Coupling with Stage 3 (why the tile is not yet enable-able)
The `sub.aitrust.remote` APIExport is a shell until a **sync-agent binds to it and publishes the
`subscriptions` resource**. That sync-agent is part of the **Stage-3 federation controller** (deployed on
prod, bound to `sub.aitrust.remote`). So after Stage 2 the tile is registered but a prod user cannot yet
Enable it — that lights up in Stage 3.

## Verification (live)
| Object | Result |
|---|---|
| workspace `root:providers:ai-trust-remote` | Ready |
| `apiexport/sub.aitrust.remote` | present |
| `providermetadata/sub.aitrust.remote` | present |
| `contentconfiguration/aitrust-ui` | present |
| `deploy/aitrust-remote-portal` (ns aitrust-remote) | 1/1 available |
| prod-local `apiexport/sub.aitrust.msp` | **still present (untouched)** |

## Files
- `stage2-remote-tile.json` — the federated portal tile (group `sub.aitrust.remote`, "on ai-trust-1" badge).
- `stage2-remote-portal.yaml` — nginx Deployment/Service serving the tile in prod ns `aitrust-remote`.
- `stage2-pm-remote-values.yaml` — aitrust-pm-app chart values for the federated provider.
- `stage2-provider.sh` — the live registration script (reruns idempotently; sources the PROD bundle lib).

## Gotcha hit
The prod bundle's cached `.state/shoot-kubeconfig.yaml` was expired ("tls: expired certificate"). Fixed
by copying a freshly-minted prod shoot kubeconfig over it before running. (Shoot kubeconfigs last ~4h.)
