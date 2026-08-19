# Stage 4 — cross-Keycloak IdP brokering (SSO, Option A)  ✅ DONE

**Task #259.** Live on ai-trust-1 **2026-08-19**. A federated tenant's a1 realm brokers prod's realm.

## What the controller does (folded into Reconcile, before store provisioning)
Per federated Subscription, the controller stamps `keycloak-broker-job.tmpl` ON ai-trust-1, which:
1. **Creates realm `fed-<org>`** on a1's mesh Keycloak (idempotent).
2. **Registers an OIDC Identity Provider `prod`** in that realm brokering PROD's realm `<baseorg>`
   (issuer `https://ai-trust-prod.../keycloak/realms/<baseorg>`, auth/token/userinfo/jwks endpoints,
   client `aitrust-fed-broker` + per-org secret, `syncMode=FORCE`, first-broker-login).
3. **Adds a hardcoded `tenant_id`=`fed-<org>` IdP mapper** so brokered logins carry the tenant claim.

So a prod user hitting the federated tenant's login is redirected to prod's Keycloak (their home IdP)
and SSO's into the a1 tenant. Only federated tenants get this; native tenants are untouched.

## Verified (live)
Broker Job `kc-broker-fed-fedtest` → **Complete**; logs show: *created realm fed-fedtest / created IdP
'prod' → prod realm fedtest / added tenant_id mapper*.

## Bug found + fixed during Stage 4 (important)
The stock operator's realm gate does a **direct HTTP call** to the mesh Keycloak. In federation the
controller runs on PROD, but the a1 mesh Keycloak is only reachable by **in-cluster DNS from a1** — so
the controller's direct call always 404'd ("no realm") even though the realm existed. **Fix:** the
federation controller does NOT re-check via HTTP; the **broker Job runs ON a1 and its success IS the
proof** the realm exists (fail-closed: no broker success → no provisioning). `checkRealmExists`/
`kcAdminToken` remain in the binary but are unused by the federation path.

## Reciprocal (prod-side) note
For the IdP to actually complete a login, prod's Keycloak realm `<baseorg>` needs a client
`aitrust-fed-broker` (redirect URI = a1 broker endpoint) with the matching secret. The broker Job wires
the **a1 side**; the prod-side client registration is the reciprocal half (wire when a real prod realm
exists for the org — `fedtest` was a synthetic test org). Provisioning + tenant isolation do not depend
on it; only the interactive SSO round-trip does.
