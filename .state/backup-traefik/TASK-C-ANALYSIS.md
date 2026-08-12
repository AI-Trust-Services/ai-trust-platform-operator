# TASK C — Durable mechanism to serve cert-p1 (LE) instead of self-signed domain-certificate

Date: 2026-08-11. STRICTLY READ-ONLY analysis. No live change made. Backup complete under
.state/backup-traefik/ (verified: garden login valid, all gets rc=0).

## The decisive root cause (why Phase-2 certRef repoint served self-signed anyway)

Traefik v3.6.12 Kubernetes **Gateway API provider** (`pkg/provider/kubernetes/gateway/kubernetes.go`):
- For each terminate listener it loads `listener.TLS.certificateRefs` secrets and appends them ALL into a
  single flat pool `conf.TLS.Certificates` via `getTLSConfig(tlsConfigs)`.
- It does NOT bind a cert to the listener hostname/SNI. It has NO reference to any TLSStore or
  defaultCertificate (grep: zero hits for tlsstore/default/defaultCertificate in that provider).

TLS handshake selection (`pkg/tls/certificate_store.go`, `GetBestCertificate`):
- On SNI, `matchDomain()` finds ALL certs whose SAN matches the server name, sorts them, and returns the
  **lexicographically last key** ("best match").
- `GetDefaultCertificate()` (the `default` TLSStore's DefaultCertificate) is returned ONLY when
  `GetBestCertificate()` returns nil — i.e. ONLY when NO SNI match exists. It does NOT override an SNI match.

Consequence for this cluster:
- BOTH secrets have SAN `*.ai-trust-1.<suffix>`:
  - domain-certificate  (self-signed, CN=ai-trust-1-mesh, CA "Standard Platform Mesh Local CA")
  - cert-p1             (real LE, CN=*.<suffix>, issuer O=Let's Encrypt CN=YR1)
- Every terminate listener refs domain-certificate, so it is in the pool. For any `*.<suffix>` host BOTH
  certs match SNI, and GetBestCertificate deterministically keeps returning domain-certificate.
- Repointing ONE listener (terminate-wildstar) to cert-p1 (Phase-2) left domain-certificate still in the
  pool via the OTHER listeners (terminate, terminate-services, terminate-aitrust, terminate-aitrust-wild),
  so the "best match" was unchanged. That is why it served self-signed even though the listener showed
  Accepted/Programmed.

## THEREFORE: the premise of Task C ("set Traefik default cert = cert-p1") is INEFFECTIVE here

Setting `tls.stores.default.defaultCertificate.secretName=cert-p1` (or a `default` TLSStore CR, or a
--providers.file default cert) would NOT change the served cert for `*.<suffix>` hosts, because those hosts
DO match an SNI cert (domain-certificate) and DefaultCertificate never overrides an SNI match. Default cert
only affects no-SNI / no-match clients. NOT the fix. (Also: the gateway provider ignores TLSStore entirely.)

## The ACTUAL durable mechanism

Remove domain-certificate from the served pool for the target hostnames by editing the AUTHORITATIVE Helm
desired-state, NOT a runtime Gateway patch (Flux reconciles the Gateway from infra values every 1m).

Two owners write the Gateway's listener certRefs:
1. HelmRelease **infra** (chart infra@0.34.0, OCIRepository infra, ns platform-mesh-system) templates
   k8sapi-gateway (annotation meta.helm.sh/release-name=infra). Its `.spec.values.gatewayApi`:
     - listeners[]:  terminate, terminate-wildstar (+ passthrough)  -> certificateRefs.name=domain-certificate
     - listenersExtra[]: terminate-services                        -> certificateRefs.name=domain-certificate
2. **SOMETHING ELSE** owns the two extra listeners on the LIVE gateway that are NOT in infra values:
     - terminate-aitrust        (host ai-trust-platform-main.<suffix>)
     - terminate-aitrust-wild   (host *.aitrust-1.<suffix>)  <-- note the DIFFERENT sub-suffix "aitrust-1"
   These 6 live listeners vs 4 in infra values => a second actor (the AI Trust standalone install's static
   routing, per project memory "dedicated terminate-aitrust listener") also merges listeners referencing
   domain-certificate. THIS MUST BE FOUND AND CHANGED TOO, or it keeps domain-certificate in the pool.
   (Unverified who patches these post-Helm — likely the operator or a standalone manifest. Needs a
   READ-ONLY managedFields / operator-source check before any change.)

Minimal durable change = change EVERY certificateRefs.name that resolves to a `*.<suffix>`-covering cert
from `domain-certificate` to `cert-p1`, at the SOURCE:
  - infra HelmRelease .spec.values.gatewayApi.listeners[*].tls.certificateRefs[0].name = cert-p1
  - infra HelmRelease .spec.values.gatewayApi.listenersExtra[*]...name = cert-p1
  - AND whatever templates terminate-aitrust / terminate-aitrust-wild (find first).
Because after that NO listener loads domain-certificate, it leaves the pool and GetBestCertificate returns
cert-p1 for `*.<suffix>` hosts. (cert-p1 SAN = `*.<suffix>` ONLY — it does NOT cover the bare apex
`ai-trust-1.<suffix>` nor `*.services.<suffix>` nor `*.aitrust-1.<suffix>`; see "cert coverage gap" below.)

Editing infra .spec.values in the LIVE HelmRelease and nudging Flux is durable (survives reconcile) because
Flux's desired state now says cert-p1. This is the correct layer. A runtime `kubectl patch gateway` is NOT
durable (reverted in ~1m).

## CERT COVERAGE GAP — a correctness blocker, not just cosmetic

cert-p1 SAN is ONLY `*.ai-trust-1.<suffix>` (single wildcard label). It does NOT match:
  - apex `ai-trust-1.<suffix>`                    (listener "terminate"  -> PORTAL + Keycloak + Dex)
  - `*.services.ai-trust-1.<suffix>`              (listener "terminate-services" -> provider service hosts)
  - `*.aitrust-1.<suffix>`                        (listener "terminate-aitrust-wild"; different label)
  - `ai-trust-platform-main.ai-trust-1.<suffix>` IS matched by `*.ai-trust-1.<suffix>` (single-label) OK.
If those listeners are switched to cert-p1, Traefik would have NO SNI match for the apex/services/aitrust-1
hosts and would fall back to GetDefaultCertificate -> Traefik's auto self-signed (or the `default` store if
set) => browser cert errors on the PORTAL and provider hosts. So a blanket swap BREAKS the portal.
=> To serve LE only on the AI Trust instance wildcard `*.ai-trust-1.<suffix>` WITHOUT breaking apex/portal,
   you must switch ONLY terminate-wildstar to cert-p1 AND remove domain-certificate from every OTHER listener
   that also matches `*.ai-trust-1.<suffix>` — but terminate (apex) and terminate-services use DIFFERENT
   hostnames not covered by cert-p1, so they legitimately still need a cert that covers them. The cleanest
   correct outcome requires a cert whose SAN covers ALL served hostnames (apex + all wildcards), i.e. either
   (a) reissue the LE Certificate cert-p1 with the full SAN set the self-signed cert has, or
   (b) keep domain-certificate for apex/services and accept that ANY `*.ai-trust-1` host will still tie-break
       to whichever cert sorts last — meaning you CANNOT reliably serve cert-p1 on instance hosts while
       domain-certificate remains loaded for the apex, because both match those hosts.
This is the core tension: SNI selection is pool-global, not per-listener. Per-listener cert isolation is not
possible in this Traefik/Gateway build for OVERLAPPING wildcard SANs.

## RANKED PITFALLS
1. SHARED mesh Traefik + pool-global SNI selection: changing certRefs affects the PORTAL, Keycloak/Dex,
   every provider service host, every tenant — NOT just AI Trust. There is NO non-shared entrypoint here
   (single LB 130.214.18.166, single websecure:8443, single cert pool). Inherently all-or-nothing per SAN.
2. cert-p1 SAN too narrow (`*.ai-trust-1` only) -> apex/portal + `*.services` + `*.aitrust-1` lose their
   cert -> TLS errors. Blocker unless cert-p1 reissued with full SAN.
3. Two owners of listener certRefs (infra HelmRelease + an unidentified actor for terminate-aitrust*).
   Editing infra alone will NOT remove domain-certificate from the pool; the other listeners keep loading it,
   so GetBestCertificate is unchanged. Must locate + change the second actor too.
4. Flux reconcile (interval 1m, remediation retries) reverts any runtime Gateway/secret patch. Durable change
   MUST be at infra .spec.values (and the 2nd owner's source). Live-edit of the HelmRelease will itself be
   reverted if a GitOps/OCM source re-pushes infra values — verify infra HR is not itself managed by an
   outer kustomization before editing (OCIRepository infra @0.34.0 is the chart, values are inline in the HR,
   so a live HR .spec.values edit should hold until the next platform re-deploy; confirm no parent kustomize).
5. Changing the DEFAULT cert (Task C literal ask) is a no-op for the goal (see above) but WOULD change what
   no-SNI clients get; low blast radius, wrong lever.

## ROLLBACK (one-command per the backup README)
If a durable infra-values change were ever made, revert with the captured working desired-state:
  export KUBECONFIG=.state/shoot-kubeconfig.yaml
  kubectl apply -f .state/backup-traefik/secrets.yaml       # both TLS secrets (idempotent)
  kubectl apply -f .state/backup-traefik/gateway.yaml       # listeners -> domain-certificate (self-heals)
  # DURABLE: re-apply infra HelmRelease .spec.values from traefik-helm-provenance.txt (lines 190-351),
  # which hard-code certificateRefs.name=domain-certificate, then let Flux reconcile (1m) or force:
  kubectl -n platform-mesh-system annotate helmrelease infra reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
Single-command fastest revert to WORKING self-signed: `kubectl apply -f .state/backup-traefik/gateway.yaml`
(re-serves self-signed within seconds; Flux/infra values already agree so it stays).

## RECOMMENDATION: NO-GO on the literal Task C (default-cert) change; and NO-GO on a blanket certRef swap.
- Setting Traefik default cert = cert-p1 will NOT achieve the goal (DefaultCertificate never overrides an SNI
  match; both certs match the instance hosts). Wrong mechanism.
- A blanket listener swap to cert-p1 would break the portal/apex/services (cert-p1 SAN too narrow) and still
  be fought by the un-identified 2nd listener owner.
- There is NO non-shared entrypoint to test on; it is inherently all-or-nothing on the shared mesh Traefik.
PRECONDITIONS before any GO:
  (a) Reissue the managed LE Certificate so cert-p1 (or a new secret) SAN covers the FULL served set:
      apex ai-trust-1.<suffix> + *.ai-trust-1.<suffix> + *.services.ai-trust-1.<suffix>
      (+ *.aitrust-1.<suffix> if that listener stays) — matching the self-signed cert's SAN.
  (b) Identify + control the 2nd actor writing terminate-aitrust / terminate-aitrust-wild certRefs.
  (c) Only then, change certRefs at the SOURCE (infra values + 2nd source) in one coordinated change,
      accept portal-wide blast radius, and keep the one-command gateway.yaml rollback ready.
If the ONLY requirement is that the LE material be SERVED and self-signed is acceptable for apex, the safest
DURABLE path is actually (a)+(c): make the served secret carry the full-SAN LE cert. The single smallest
durable knob that is CORRECT = point every listener certRef at ONE secret that holds a full-SAN LE cert.
