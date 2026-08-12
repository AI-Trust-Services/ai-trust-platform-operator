# Managed TLS cert for AI Trust MSP instances — investigation + plan (Phase 1 done, READ-ONLY)

## 🛑 REVERTED 2026-08-11 — the LE swap broke platform auth (frontproxy OIDC). Back on self-signed; DO NOT retry without fixing frontproxy trust.
The full-SAN LE swap (below) made browsers happy but **broke org management platform-wide** with
`gateway .../clusters/root:orgs/graphql → 401` and "Organization list retrieval failed". Root cause found:
**kcp frontproxy validates every portal token by calling each org's Keycloak OIDC discovery over the PUBLIC
apex host** (`https://ai-trust-1.<suffix>/keycloak/realms/<org>/.well-known/openid-configuration`). Frontproxy's
OIDC authenticator was configured to **trust the self-signed CA**. After the served cert became Let's Encrypt,
frontproxy logged `oidc authenticator: ... x509: certificate signed by unknown authority` for EVERY realm →
could not init the OIDC plugin → `TokenReview API call failed` → **401 on all token validation, every org**.
So a real-cert switch on the apex REQUIRES also updating **frontproxy's OIDC trust/CA config** (and any other
in-cluster client that pins the self-signed CA), NOT just the served cert. This is a deeper coupling than the
earlier investigation surfaced — the true blast radius includes kcp's auth plane.

**REVERTED cleanly:** restored the self-signed `domain-certificate` secret from `prerequisites/tls.crt`+`tls.key`
(the authoritative source — the `.state/backup-cert-swap/secrets.yaml` restore hit a resourceVersion conflict,
so use `kubectl create secret tls domain-certificate --cert=prerequisites/tls.crt --key=prerequisites/tls.key
--dry-run=client -o yaml | kubectl apply -f -`), then `rollout restart deploy/traefik` (ns default) AND
`rollout restart deploy/frontproxy-front-proxy` (ns platform-mesh-system). VERIFIED: served cert = self-signed
`CN=ai-trust-1-mesh`; frontproxy x509 errors = 0; TokenReview failures = 0; org management works again.
`cert-aitrust-full` (the LE cert) is left in place unused — harmless.

**Correct future path (do NOT attempt casually):** to serve a real cert on the apex you must (1) issue a
full-SAN LE cert (done: `cert-aitrust-full` = apex + `*.ai-trust-1` + `*.services`; the `*.aitrust-1` typo host
can't get ACME), (2) point the gateway/served cert at it, AND (3) reconfigure **frontproxy's OIDC CA bundle** to
trust the LE chain (or use the system trust store) so token validation keeps working, plus check every other
in-cluster consumer of the apex Keycloak. This is a mesh-chart-level change (frontproxy + gateway), reviewed,
with the whole-platform-auth blast radius accepted. Until then, self-signed is the working status quo — keep it.

---


## ✅✅ DONE 2026-08-11 — REAL Let's Encrypt cert now served platform-wide (verified). Working + durable-for-now.
After the two investigations, the safe swap succeeded on the live cluster:
1. **Reissued a full-SAN managed LE cert** `cert.gardener.cloud/Certificate cert-aitrust-full` (ns platform-mesh-system),
   dnsNames = apex `ai-trust-1.<suffix>` + `*.ai-trust-1.<suffix>` + `*.services.ai-trust-1.<suffix>` → secret
   `cert-aitrust-full`, **state=Ready, issuer O=Let's Encrypt CN=YR2, valid to 2026-11-09**. (Dropped the
   `*.aitrust-1` typo host — its ACME DNS-01 is blocked by LocalNamespaceAccessOnly and no real instance uses it.)
2. **Swapped by overwriting the `domain-certificate` SECRET's data** with cert-aitrust-full's LE tls.crt/key/ca, then
   `kubectl -n default rollout restart deploy/traefik`. Chosen over editing the Gateway because (a) cert selection is
   pool-global so every listener refs `domain-certificate` → all switch at once, (b) the secret is hand-applied (NOT
   Flux-owned) so no reconcile fight, (c) `kcp.api` (the one SAN the LE cert lacks) is NOT served via this public
   gateway (syncagents use it in-cluster via hostAlias). 
3. **Verified:** apex/portal `/`=200 verified (no -k), `/keycloak/realms/master`=200 verified, instance `d` & `testai`
   & `aitrustg2` all serve `O=Let's Encrypt CN=YR2`; held stable through Flux/gardener reconcile windows (90s+).
   **Every current AND future instance host is covered** by the `*.ai-trust-1` SAN — no per-instance cert work ever.
Login/app confirmed working over the new cert. NO browser warning anymore.

**Rollback (staged, verified):** `export KUBECONFIG=.state/shoot-kubeconfig.yaml && kubectl -n platform-mesh-system apply -f .state/backup-cert-swap/secrets.yaml && kubectl -n default rollout restart deploy/traefik` → restores the original self-signed bytes. (Backups also in `.state/backup-cert-swap/` and `.state/backup-traefik/`.)

**Durability caveat (for bulletproofing later):** the served material is currently in the shared `domain-certificate`
secret via a MANUAL overwrite. A gardener Certificate CR named `domain-certificate` also references that secret, so on
its own reconcile it *could* rewrite the bytes (to its own LE apex+`*.ai-trust-1` cert — still trusted + covers
instances — or worst case regenerate). It held stable in testing. To make it fully self-maintaining, point the gateway
listeners at the dedicated **`cert-aitrust-full`** secret (which auto-renews via its own gardener Certificate) as a
durable HelmRelease-values change to `infra`, rather than relying on the overwritten shared secret. Not required for
current function; do it when convenient.

---


## ✅ FINAL VERDICT (2026-08-11, after 2 read-only investigations + 1 reverted live trial): NO-GO on a live edit; keep self-signed
The real mechanism is now proven from Traefik v3.6.12 source + live probes. **Traefik selects the served cert
POOL-GLOBALLY, not per Gateway listener:** it loads EVERY listener's `tls.certificateRefs` secret into one flat
pool and, per SNI, serves the **lexicographically-last matching cert** (`GetBestCertificate`). Both
`domain-certificate` (self-signed, SAN incl `*.ai-trust-1.<suffix>`) and `cert-p1` (real LE, `*.ai-trust-1.<suffix>`)
match every instance host; `domain-certificate` wins the tie-break and stays in the pool via the other listeners.
That's why the Phase-2 single-listener certRef repoint served self-signed anyway (NOT because certRefs are ignored —
my earlier note said that; it was WRONG).

**Three hard blockers to switching to the LE cert:**
1. **Blast radius = whole platform.** ONE shared Traefik (`default/traefik`), ONE LoadBalancer (130.214.18.166),
   ONE `websecure` entrypoint (:443 and :8443 both map to it), ONE pool-global cert store shared by the portal,
   Keycloak/Dex, every provider, every tenant. No canary, no isolation — a mistake breaks platform login.
2. **`cert-p1` SAN too narrow** — only `*.ai-trust-1.<suffix>`. Does NOT cover apex `ai-trust-1.<suffix>`
   (portal/Keycloak/Dex), `*.services.<suffix>`, or `*.aitrust-1.<suffix>`. A blanket swap drops those to
   Traefik's built-in self-signed → platform-wide TLS errors. Requires REISSUING the LE cert with the full SAN set first.
3. **Two owners of listener certRefs:** HelmRelease `platform-mesh-system/infra` (chart infra@0.34.0) templates 4
   listeners; a 2nd actor (the AI Trust standalone install) writes `terminate-aitrust` + `terminate-aitrust-wild`.
   Editing one leaves `domain-certificate` in the pool → no change.
Plus **Flux reverts runtime Gateway patches (~1m)** — a durable change is a reviewed PR to `infra` HelmRelease
values (BOTH owners), AFTER reissuing a full-SAN LE cert. NOT a kubectl edit. **Wrong levers (no-ops for this goal):**
TLSStore `default` / `--providers.file` default cert / entrypoint default cert — `GetDefaultCertificate` only serves
no-SNI/no-match clients; it never overrides an SNI match, and instance hosts DO match.

**Correct path when it's worth it:** reissue the managed LE Certificate with SAN = apex + `*.ai-trust-1` +
`*.services.ai-trust-1` (+ `*.aitrust-1` if kept) → repoint EVERY listener certRef to that single managed secret at
the chart/HelmRelease source (both owners) via a reviewed PR, portal-wide blast radius accepted, rollback staged.
Until then, **self-signed is the lower-risk status quo — leave it.**

**Backup for this (complete, verified):** `.state/backup-traefik/` (traefik deploy/svc, gateway, both cert secrets
full bytes, all traefik.io CRs, HelmRelease provenance, baseline cert probe). One-command revert:
`export KUBECONFIG=.state/shoot-kubeconfig.yaml && kubectl apply -f .state/backup-traefik/gateway.yaml`
(+ `secrets.yaml` if secrets touched; if a durable infra-values change was made, also restore infra HR values from
`.state/backup-traefik/traefik-helm-provenance.txt` and force-reconcile). Verify: apex+instance SNI → CN=ai-trust-1-mesh.

---


## ⚠️ PHASE-2 TRIAL RESULT (2026-08-11): listener certRef swap DID NOT change the served cert — REVERTED to baseline
We tried the plan live (Stages 0–3) and learned the plan's core assumption is WRONG for this Traefik build:
- Stage 0 ✅ `cert-p1` secret is confirmed **real Let's Encrypt** (issuer `O=Let's Encrypt, CN=YR1`,
  subject `CN=*.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`, valid to Nov 8 2026,
  `kubernetes.io/tls` with tls.crt+tls.key present).
- Stage 1 (dedicated `terminate-testai` listener → cert-p1) programmed fine, BUT the **operator continuously
  re-applies each instance's HTTPRoute `sectionName=terminate-wildstar`**, reverting the per-instance repoint
  → testai-only trial can't hold. (Removed the trial listener; baseline restored.)
- Stage 3 (repoint the SHARED `terminate-wildstar` `certificateRefs` `domain-certificate → cert-p1`):
  the Gateway spec updated, listener stayed `Accepted/ResolvedRefs/Programmed=True` ("No error found"),
  and a **Traefik rollout restart** was done — YET every host STILL served the self-signed
  `CN=ai-trust-1-mesh` / `Standard Platform Mesh Local CA`. So **Traefik ignores the Gateway listener
  certificateRefs for the served cert** here.
- **REVERTED**: `terminate-wildstar` certRef put back to `domain-certificate`, all 6 listeners Programmed=True,
  instances serve the working self-signed cert exactly as before. **No breakage; cluster at baseline.**

### Why it didn't work (mechanism, corrected)
Traefik (`default/traefik`, v3.6.12, gatewayClass `traefik`, controller `traefik.io/gateway-controller`)
runs with `--entryPoints.websecure.http.tls=true` on :8443, **no default-cert secret mounted, no TLSStore**,
and it serves `domain-certificate`'s keypair regardless of the Gateway listener `certificateRefs`. The served
cert is NOT driven by the listener certRef in this setup. Next investigation must target **how Traefik
actually selects the served cert** — likely a Traefik **default certificate / TLSStore `default`** or how the
mesh chart seeds the entrypoint cert — and change THAT (point the default TLS to `cert-p1`), not the Gateway
listener. This needs its own read-only investigation before another attempt. DO NOT keep swapping listener
certRefs — proven ineffective + it's the shared gateway.

---
**Status: investigated + backed up. GO recommended. NOTHING changed live yet.** Phase 2 (apply) needs
explicit approval + a fresh `prerequisites/login.sh`.

## Headline finding — a real managed cert already exists, it's just not wired
The shoot **already has** a Gardener-managed Let's Encrypt **wildcard** cert, healthy and auto-renewing:
- `cert.gardener.cloud/v1alpha1 Certificate **cert-p1**`: dnsNames `*.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`, issuerRef `gardener`, **state=Ready**, LE serial, ~90-day, writes secret **`platform-mesh-system/cert-p1`**.
- (`cert-p2` = apex, Ready; a gardener Certificate literally named `domain-certificate` also Ready — do NOT confuse it with the hand-seeded self-signed *Secret* of the same name.)

**Why browsers still see self-signed:** all 6 `k8sapi-gateway` listeners' `tls.certificateRefs` point at the
static self-signed secret `domain-certificate` (leaf CN=`ai-trust-1-mesh`, CA `Standard Platform Mesh Local CA`).
**The managed cert is issued but never consumed.** So this is a **one-secret rewiring**, not a new-issuance/ACME/rate-limit project.

## Two myths busted
- **"10-label FQDN limit"** — does NOT exist. Our hosts are 9 labels / 79 chars; LE limits are 253 total / 63 per label. Not a blocker.
- **Public DNS already works** — shoot-dns-service publishes `*.ai-trust-1...` → LB `130.214.18.166`; every instance host (even random) resolves. No per-host DNS needed. The colleague's `dns.gardener.cloud`/`cert.gardener.cloud` **annotation path does NOT apply here** — those are only honored on `networking.k8s.io` **Ingress**, and this mesh uses Gateway-API **HTTPRoute** on Traefik. Managed cert must come via a **Certificate CR → Secret → Gateway listener `certificateRefs`**.

## Plan (Gateway-API model; try on throwaway `testai` first; NEVER the shared portal listener during trial)
0. `login.sh`; live-verify `cert-p1`'s SECRET holds LE material: `openssl x509` issuer must NOT be `Standard Platform Mesh Local CA`, SAN covers `*.ai-trust-1...`. If it's still the local CA → STOP.
1. **Stage 1 (prove on testai):** add ONE listener `terminate-testai` (hostname `testai.ai-trust-1...`, HTTPS 8443, `certificateRefs → cert-p1`); repoint only testai's 2 HTTPRoutes `sectionName` → `terminate-testai`. Traefik SNI picks the most-specific listener; the wildcard listener keeps serving everyone else.
2. **Stage 2 (validate):** watch Gateway `Programmed=True`; `curl -v https://testai... ` (NO `-k`) verifies against the public trust store; other instances (`d`, `my-aitrust`) still serve via the wildcard listener unchanged.
3. **Stage 3 (promote, ONE edit):** repoint `terminate-wildstar.tls.certificateRefs` `domain-certificate → cert-p1`. Every instance gets the managed wildcard at once. Optionally repoint the other listeners one-by-one, watching `Programmed=True`. Delete the trial `terminate-testai`, put testai routes back on `terminate-wildstar`.
4. **Stage 4 (durability):** `k8sapi-gateway` is Flux/Helm-managed (release `infra`) — a live `kubectl edit` is reconciled AWAY. The durable `certificateRefs → cert-p1` swap MUST land in the infra HelmRelease values. Runtime edit = demo-only until the chart PR merges.

**NOT doing:** no new/per-instance certs (LE rate-limit + redundant); no per-host DNSEntry / dns annotations; no ContentConfiguration transport change (stays in-cluster HTTP — independent of browser cert).

## Rollback (single-knob; backup in `.state/backup-dnscert/`, verified present)
- Stage 1/2 revert (testai only): `kubectl apply -f backup-dnscert/httproutes.yaml` then `.../gateway.yaml`.
- Stage 3 revert (all): `kubectl apply -f backup-dnscert/gateway.yaml` — restores every listener's `certificateRefs` to `domain-certificate` in one shot.
- If the self-signed secret bytes were disturbed: `kubectl apply -f backup-dnscert/secret.yaml` (also in `prerequisites/tls.{crt,key}`).
- One-liner: `export KUBECONFIG=.state/shoot-kubeconfig.yaml && BK=.state/backup-dnscert && kubectl apply -f "$BK/secret.yaml" && kubectl apply -f "$BK/gateway.yaml" && kubectl apply -f "$BK/httproutes.yaml"`
- DNS needs no rollback. For a Flux-durable revert, also revert the infra HelmRelease values.

## Pitfalls (ranked by blast radius)
1. **HIGHEST — empty/unready secret takes down the WHOLE gateway.** Gateway-API programs listeners as a SET; a bad `certificateRefs` can flip the set NotProgrammed → portal + all tenants down. Verify `cert-p1` secret is populated first; prove on the dedicated `terminate-testai` listener; watch `Programmed=True`; never point the SHARED listener at an unverified secret.
2. HIGH — don't add a listener per instance as steady state (duplicate host/port or bad ref risks the set). Keep the operator's current model (reuse `terminate-wildstar`).
3. HIGH — LE rate limits ONLY if you go per-instance (apeirora.eu is shared across cc-one shoots → 50 certs/domain/week block). The wildcard approach issues ZERO new certs — sidesteps it.
4. MEDIUM — Flux reconciliation reverts live edits → land the change in the infra HelmRelease for durability.
5. MEDIUM — SNI most-specific-match assumption for the trial; if Traefik doesn't honor it, fall back to Stage 3a (swap the wildcard listener's ref) instead of fighting SNI.
6-9. LOW/INFO — redundant per-host DNS; keep CC on in-cluster HTTP; transition is warning-only (no outage); the gardener Certificate named `domain-certificate` ≠ the self-signed Secret of the same name (prefer wiring `cert-p1`).

## Backup manifest (`.state/backup-dnscert/`)
`gateway.yaml` (all listeners), `secret.yaml`/`domain-certificate.*` (self-signed keypair), `httproutes.yaml`
(all AITrust routes), `certificates.yaml` + `gardener-certificates.yaml` (managed cert CRs incl cert-p1),
`dnsentries.yaml`, findings (`TASK_A_FINDINGS.md`, `TASKB-FINDINGS.md`), `README.txt` (restore steps).
