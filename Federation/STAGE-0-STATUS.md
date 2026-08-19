# Stage 0 — garden login + reachability re-confirm  ✅ DONE

**Task #255.** Gate for all federation cluster work. Completed **2026-08-19**.

Stage 0 proves the federation mechanism's core assumption is physically possible before any code is
written: that a **prod-side controller can reach ai-trust-1's shoot API**.

## Checks performed + results

### 0.1 Garden login live
`kubectl --kubeconfig <garden> get shoots -n garden-ai-trust` → **OK**. Both shoots healthy:

| Shoot | Provider/Region | K8s | Status | Age |
|---|---|---|---|---|
| `ai-trust-1` | openstack / eu-de-1 | 1.34.3 | Reconcile Succeeded (100%) healthy | 9d |
| `ai-trust-prod` | openstack / eu-de-1 | 1.34.3 | Reconcile Succeeded (100%) healthy | 2d15h |

(garden project `garden-ai-trust`, API `https://api.garden.gardener.cc-one.showroom.apeirora.eu`)

### 0.2 Both shoot admin kubeconfigs minted (4h)
Via Gardener `AdminKubeconfigRequest` (`expirationSeconds: 14400`) against each shoot in
`garden-ai-trust`:
- `ai-trust-prod` → minted, `get ns` → **reachable + authed**.
- `ai-trust-1` → minted, `get ns` → **reachable + authed**.

Shoot API endpoints:
- ai-trust-prod: `https://api.ai-trust-prod.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`
- ai-trust-1:   `https://api.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`

### 0.3 **Prod → ai-trust-1 shoot API reachability (the decisive check)**
From **inside a prod pod** (`compliance-backend` in ns `aitrust-msp`, chosen because the operator pod is
distroless / has no shell), a request to the ai-trust-1 shoot API:

```
GET https://api.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/version
→ http_code=401
```

**Interpretation: PASS.** `401` (not a timeout / DNS failure / connection refused) means:
- DNS resolves and the TCP+TLS connection to ai-trust-1's shoot API **succeeds from within prod**;
- the **only** thing rejecting the call is **authentication** — exactly what a mounted ai-trust-1 shoot
  kubeconfig (Stage 1) will supply.

So the prod-side federation controller **will** be able to provision on ai-trust-1 once it holds valid
a1 credentials. The network path is open; auth is the sole gate. Matches the earlier probe (prod→a1
shoot API 401) from the planning phase.

## Conclusion
Stage 0 is satisfied — federation via the **shoot-API mechanism** is feasible. Proceed to **Stage 1**
(mint/store the a1 credential in prod ns `aitrust-remote` + refresh).

## Notes
- The shoot kubeconfigs minted for this check are **short-lived (~4h)** scratch files and are not kept in
  this bundle. Stage 1 defines the durable, refreshable credential.
- Probe pod choice matters: distroless images (operator) have no shell; use a Python/`sh`-capable pod.
