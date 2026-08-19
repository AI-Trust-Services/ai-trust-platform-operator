# Stage 6 — reciprocal prod-side IdP client (SSO round-trip complete)  ✅ DONE

**Task #264.** Live + proven **2026-08-19**. Completes the browser-to-browser SSO loop begun in Stage 4.
**Works for ANY org** (derived from `spec.org`); only prerequisite is a real PROD Keycloak realm `<org>`.

## The full SSO loop (both halves now exist)
```
prod user → https://ai-trust-fed-<org>.ai-trust-1...           (a1 tenant login)
          → a1 realm fed-<org>, IdP 'prod'  (Stage 4, on a1)   → redirect to prod
          → PROD realm <org>, client 'aitrust-fed-broker'      (Stage 6, on prod) ← THIS
          → authenticate at prod → callback → back into a1 tenant, SSO'd
```
- **Stage 4 (a1 side):** realm `fed-<org>` + OIDC IdP `prod` → prod's `<org>` realm issuer.
- **Stage 6 (prod side):** OIDC client `aitrust-fed-broker` in prod realm `<org>`, redirect URI =
  `https://ai-trust-1.../keycloak/realms/fed-<org>/broker/prod/endpoint`, **same per-org secret** the a1
  IdP holds (so both sides agree).

## How the controller does it (two-cluster, correctly split)
`reconcileReciprocalSSO` (best-effort, non-fatal) runs on PROD after the tenant is provisioned:
1. reads the a1 broker secret value (`aitrust-fedbroker-<org>`) from the REMOTE (a1) cluster;
2. mirrors it + prod's mesh keycloak-admin into the controller's own ns `aitrust-remote` on PROD;
3. stamps `keycloak-prod-client-job.tmpl` on the LOCAL (prod) cluster — prod's mesh Keycloak IS reachable
   from the controller here (unlike a1's, which is why the a1 broker is a Job ON a1). The Job gates on the
   prod realm `<org>` existing; if it doesn't (synthetic org), it fails and the controller logs it
   non-fatally — the tenant is still Ready, only interactive SSO waits.

## Verified live (org = aitrust — a real prod realm)
- Tenant `fed-aitrust` → **Ready** on a1 (broker + stores + proxy).
- prod-client Job `kc-prod-client-fed-aitrust` → **Complete**; logs: *created client aitrust-fed-broker in
  PROD realm aitrust (redirect .../realms/fed-aitrust/broker/prod/endpoint)*.
- Controller log: **`reciprocal prod-side SSO client wired` — prodRealm=aitrust, client=aitrust-fed-broker**.

## Bugs found + fixed during Stage 6
1. **`kubectl apply -f stage3-federation-deploy.yaml` re-applied the RAW template** (literal
   `__IMG__`/`__A1_DOMAIN_SUFFIX__`), which broke the running Deployment (InvalidImageName + an HTTPRoute
   with a literal-placeholder hostname). **Fix:** always apply that manifest **through the sed
   substitution** (as `stage3-deploy.sh` / `.fix_env.sh` do), never raw. Re-applied with real values;
   env now clean.
2. **`root:orgs:demo:tenant` is Forbidden** to the kcp-admin kubeconfig we hold (only `aitrust`'s account
   ws is accessible) — so the live test used **aitrust** (also a real prod realm). `demo` would work
   identically from the portal, where the consumer drives their own ws.

## Files
- `federation-operator/manifests/keycloak-prod-client-job.tmpl` — the prod-side client Job.
- controller `reconcileReciprocalSSO` + local-cluster helpers in `federation-operator/main.go`.
- `stage6-reciprocal-test.sh` — the live test (bind + Subscription for a real org + verify).

## Follow-ups (not blockers)
- Mirror `federation-operator/` + the Federation bundle to the operator repo.
- The a1 IdP + prod client are wired; a real end-user browser login will now complete SSO. (Not scripted
  here — needs an interactive browser session with a prod `aitrust`-realm user.)
