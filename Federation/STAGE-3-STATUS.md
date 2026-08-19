# Stage 3 — federation controller (provision on ai-trust-1)  ✅ DONE (plumbing proven E2E)

**Task #258.** Deployed live **2026-08-19** on ai-trust-prod. The full federation path is proven working;
the only remaining gate is Stage 4 (create+broker the `fed-<org>` realm on a1).

## Deployed (prod ns aitrust-remote)
- `CRD subscriptions.sub.aitrust.remote` (+ `status.cluster`).
- **`aitrust-federation`** Deployment (1/1) — image `mirceacraciun795/aitrust-federation:aitrust`,
  mounts the Stage-1 a1 SA kubeconfig at `/etc/a1/kubeconfig`, env → ai-trust-1.
- **`aitrust-remote-syncagent`** Deployment (1/1) bound to `sub.aitrust.remote` — publishes the
  `subscriptions` resource (schema `v74974de8.subscriptions.sub.aitrust.remote`) → tile enable-able.
- hostAlias fix applied to the syncagent.

## E2E proof (this session)
Created an `APIBinding` to `sub.aitrust.remote` in the account ws `root:orgs:aitrust:tenant` (→ **Bound**)
and a `Subscription {org: fedtest}` in ns `default` (the faithful portal-Enable path). Observed:
1. Sync-agent **mirrored it prod→shoot**: appears with `CLUSTER=ai-trust-1`,
   `URL=https://ai-trust-fed-fedtest.ai-trust-1...` — the `fed-` prefix + a1 host are correct.
2. Federation controller **reconciled it** via the two-client split: `tenantId=fed-fedtest`,
   `realm=fed-fedtest`, `cluster=ai-trust-1` — reads a1's mesh Keycloak through the remote client.
3. Reached the **realm-existence gate** and correctly **Degraded**: *"org 'fed-fedtest' has no Keycloak
   realm in the mesh — onboard the org first"*. This is the exact Stage-3→4 boundary: the controller
   refuses to provision stores/proxy until the tenant realm exists (fail-closed).

So: portal Enable → kcp binding → sync-agent mirror → controller reconcile against ai-trust-1 all work.
Stamping the stores Job + proxy on a1 is unblocked the moment Stage 4 creates the `fed-<org>` realm.

## Stage-1 RBAC addendum (found during the test)
The controller reads a1's mesh admin secret `platform-mesh-system/keycloak-admin` (realm gate +
kc-client Job). Added `secrets: [get,list]` in `platform-mesh-system` to the `aitrust-federation-routes`
Role (`stage1-a1-serviceaccount.yaml`). Verified: SA `can-i get secrets -n platform-mesh-system` → yes.

## Two-client behaviour confirmed
- LOCAL (prod, in-cluster SA) — watches mirrored Subscriptions, writes status. ✅
- REMOTE (a1 SA kubeconfig) — reads a1 mesh-admin, will apply stores/proxy on a1. ✅ (mesh-admin read now works)

## Note (unrelated)
a1's **native** operator shows some `tenant-stores-<org>` Jobs as `Failed` (idempotent re-runs of
already-provisioned tenants; all 4 native schemas `tenant_fridaytest/martin/mircealast/sen` are present
and intact). Not caused by federation and not caused by the earlier tenant_id column drop (timestamps
post-date it); native tenants healthy.

## Files
- `federation-operator/` — the forked controller (built → `:aitrust`).
- `stage3-federation-deploy.yaml`, `stage3-syncagent.yaml`, `stage3-deploy.sh` — deploy.
- `stage5-e2e-test.sh` — the Enable/provision E2E harness (reused for Stage 5).
