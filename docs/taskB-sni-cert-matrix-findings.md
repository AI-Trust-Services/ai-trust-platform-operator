# Task B — READ-ONLY SNI/port cert verification (2026-08-11)

## Verdict
**Traefik DOES honour the Gateway listener `tls.certificateRefs`.** It serves a
per-listener cert selected by SNI — NOT one single default cert for everything.
Therefore the earlier "repoint certRef → no effect" trial did NOT fail because
certRefs are ignored; it failed for another reason (see below).

## Served-cert matrix (LB 130.214.18.166, authoritative leaf via `s_client -showcerts`)
Identical on **:443 and :8443** (443 is just a second Service port fronting the same
`websecure` entrypoint — see ports section; no separate TLS config).

| SNI (host)                                   | matches listener            | listener certRef      | served leaf CN            | issuer                          |
|----------------------------------------------|-----------------------------|-----------------------|---------------------------|---------------------------------|
| `testai.<suffix>` (instance)                 | `terminate-wildstar` (`*.<suffix>`) | domain-certificate | `ai-trust-1-mesh`        | Standard Platform Mesh Local CA |
| `25veqwflh7syq7fm-d.<suffix>` (instance)     | `terminate-wildstar`        | domain-certificate    | `ai-trust-1-mesh`         | Standard Platform Mesh Local CA |
| `portal.<suffix>`                            | `terminate-wildstar`        | domain-certificate    | `ai-trust-1-mesh`         | Standard Platform Mesh Local CA |
| `<suffix>` (bare/apex)                        | `terminate` (exact apex)    | domain-certificate    | `ai-trust-1-mesh`         | Standard Platform Mesh Local CA |
| `nope-XXXX.<suffix>` (random wildcard)       | `terminate-wildstar`        | domain-certificate    | `ai-trust-1-mesh`         | Standard Platform Mesh Local CA |
| `foo.services.<suffix>`                      | `terminate-services` (`*.services.<suffix>`) | domain-certificate | **`TRAEFIK DEFAULT CERT`** | TRAEFIK DEFAULT CERT           |

The `*.services` case is the smoking gun: same certRef in spec (`domain-certificate`),
but a DIFFERENT cert is served (Traefik's built-in). That proves selection is per-listener,
not a global default — i.e. certRefs matter. (The `*.services` listener's certRef is very
likely not actually resolvable/loaded by Traefik, so it falls back to the built-in default
cert for that listener only.)

## Why the earlier trial "served self-signed after repointing to cert-p1"
Not because certRefs are ignored. The plausible causes, in order:
1. **Reload lag / caching** — Traefik-hub keeps the previously-loaded TLS material; a
   rollout restart may have raced the Gateway status update, so it re-read the OLD certRef.
2. **Cross-namespace certRef not permitted** — cert-p1 lives in `platform-mesh-system`;
   listeners resolved it as `ResolvedRefs=True` in status, but Traefik's Gateway provider
   may require a `ReferenceGrant` or same-namespace secret to actually LOAD it, silently
   falling back to the last-known-good (domain-certificate) or the built-in default.
   NOTE the `*.services` listener already demonstrates the "certRef present but not loaded →
   built-in default" fallback, so this failure mode is real on this cluster.
3. Only the leaf was checked (subject=CN) without `-showcerts`; `openssl x509` on a bare
   `s_client` pipe can mis-parse which block it decodes (our first matrix run printed
   "TRAEFIK DEFAULT CERT" for instance hosts, but `-showcerts` first-block proved it is
   actually `ai-trust-1-mesh`). So earlier "still self-signed" reads may have been partly
   a probe artifact.

## Ports: :443 vs :8443
Both terminate on the SAME traefik `websecure` entrypoint (`:8443/tcp`, `http.tls=true`).
Service `default/traefik` maps two ports to the same `targetPort websecure`:
`websecure 8443→websecure` and `websecure-443 443→websecure`. So :443 and :8443 are
identical TLS-wise — confirmed by the matrix (same certs on both).
Traefik has NO default-cert secret volume mounted; NO TLSStore exists
(`kubectl get tlsstore -A` = only header). Its built-in self-signed "TRAEFIK DEFAULT CERT"
is the last-resort fallback when a matched listener's certRef is not loadable.

## Implication for the goal (serve real LE cert-p1)
Because certRefs ARE honoured per-listener, the fix is at the **certRef layer**, not a
hidden global default. To serve cert-p1 on instance hosts:
- Repoint `terminate` + `terminate-wildstar` (and the aitrust ones) certRefs → `cert-p1`, AND
- ensure Traefik can actually LOAD cert-p1: confirm a `ReferenceGrant` exists if the Gateway
  and secret are treated as cross-namespace by the traefik provider, and force a clean
  Traefik reload (not just a status flip). The `*.services` fallback shows an unloadable
  certRef silently degrades to the built-in cert — so "ResolvedRefs=True" in Gateway status
  is NOT sufficient evidence that Traefik loaded it.
- A single default-cert (TLSStore `default` or `--providers.file` default cert) would ALSO
  fix everything at once, but none exists today; adding one is the alternative lever.

(All READ-ONLY. Backups in `.state/backup-taskB/`.)
