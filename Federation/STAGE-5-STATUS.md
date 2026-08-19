# Stage 5 — E2E verification + teardown  ✅ DONE

**Task #260.** Verified live **2026-08-19**. The full federation flow works end to end.

## E2E provisioning (proven)
`APIBinding sub.aitrust.remote` in account ws `root:orgs:aitrust:tenant` → **Bound**; created a
`Subscription {org: fedtest}` (the faithful portal Enable). Result: **`phase=Ready`**, and ON ai-trust-1:
- `kc-broker-fed-fedtest` Complete (realm `fed-fedtest` + IdP brokering prod `fedtest`)
- `kc-client-fed-fedtest` Complete (oauth2-proxy OIDC client)
- `tenant-stores-fed-fedtest` Complete → **schema `tenant_fed_fedtest`** + CH db + MinIO bucket
- HTTPRoute **`aitrust-fed-fedtest`** → `https://ai-trust-fed-fedtest.ai-trust-1...`

## Invariants (all pass)
| # | Invariant | Result |
|---|---|---|
| INV1 | prod-local provider `sub.aitrust.msp` intact | ✅ present |
| INV2 | both tiles present | ✅ "AI Trust Platform" + "AI Trust Platform (on ai-trust-1)" |
| INV3 | a1 native tenants untouched | ✅ fridaytest/martin/mircealast/sen intact; fed_fedtest added |
| INV4 | prod-local tenants untouched | ✅ aitrust/demo/demo-aitrust intact |
| INV5 | federated tenant isolation on a1 | ✅ `t_fed_fedtest` → tenant_fridaytest = **permission denied for schema** |

## Teardown (proven)
Deleted the federated Subscription (Disable). The controller finalizer removed a1
`oauth2-proxy-fed-fedtest` + HTTPRoute `aitrust-fed-fedtest` (**both gone**), while **schema
`tenant_fed_fedtest` was preserved** (append-only data policy — Disable never deletes tenant data).

## Net result
A prod-portal Enable of the federated tile provisions an isolated, SSO-brokered tenant ON ai-trust-1
(host `ai-trust-fed-<org>.ai-trust-1`), collision-free (`fed-` prefix), with the prod-local provider and
all existing tenants on both clusters unaffected. Disable cleans up the login path and keeps the data.

## Known follow-ups (not blockers)
- **Reciprocal prod-side IdP client** for a *real* org realm (see STAGE-4). `fedtest` was synthetic.
- **Stage-1 RBAC** grew during testing to what the controller actually needs (secrets/jobs/deployments/
  services/referencegrants CRUD in aitrust-msp; httproutes+referencegrants+secrets in
  platform-mesh-system). Final set is in `stage1-a1-serviceaccount.yaml`.
- **Mirror** the federation-operator + Federation bundle to the operator repo per project convention.
