# TASK A — Managed DNS + Managed Cert extensions on shoot ai-trust-1: availability vs blocked

Phase: READ-ONLY + BACKUP. NO live resource was changed. This session's garden login is EXPIRED
(oidc-login exec plugin → interactive browser flow → hangs/cancels in non-interactive WSL), so live
`get/describe` against garden/shoot/kcp was not possible. Findings below are from (a) the expired-login
probe results and (b) live-validated prior-run evidence recorded in sibling bundles on THIS SAME shoot.

## Live-access status THIS session
- garden API: UNREACHABLE — `garden get shoot` → oidc-login browser prompt, rc=124 (timeout).
  Kubeconfig user = `oidc-login` exec plugin (no cached token/cert). → needs prerequisites/login.sh.
- shoot ai-trust-1: transitively unreachable (kubeconfig must be minted via garden adminkubeconfig).
- kcp: transitively unreachable (port-forward runs through the shoot).
- Verdict to report: "garden login expired — needs prerequisites/login.sh".

## DNS extension — shoot-dns-service: INSTALLED + HEALTHY + PROVEN
Evidence (Standard_Platform_Mesh/.state/deploy3.log, live run on ai-trust-1):
  "shoot-dns-service active (managed DNS)"  (from shoot-info CM `.data.extensions` + shoot spec.extensions)
Evidence (Gardener_DNS proof, validated live 2026-08-10 on ai-trust-1):
  - CRD dnsentries.dns.gardener.cloud PRESENT.
  - A DNSEntry (class: garden) for a host under *.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
    reaches status.state=Ready via provider `openstack-designate` AND resolves publicly.
  - The mesh gateway Service uses the annotation path (dns.gardener.cloud/class + dnsnames) to publish
    base + wildcard *.<domain> records (DEPLOYMENT_RECORD: "base and wildcard published").
=> Managed public DNS is AVAILABLE for any host under the shoot's own Gardener domain, both via DNSEntry
   CR and via Service/Gateway annotations. Per-instance MSP hosts (<id>-<name>.ai-trust-1.ai-trust.shoot...)
   ARE under this zone, so managed DNS would work for them.

## Cert extension — shoot-cert-service: INSTALLED, but ACME/managed ISSUANCE is BLOCKED for this domain
Evidence (deploy3.log): "shoot-cert-service active (managed TLS)" + CRD certificates.cert.gardener.cloud present.
BUT the SAME deploy3.log shows the managed path FAILING in practice:
  "Requesting domain-certificate via Gardener cert-service for ai-trust-1.ai-trust.shoot... (+ wildcard + kcp.api)"
  "Waiting for: domain-certificate issued by Gardener cert-service (timeout 600s)"
  "timeout waiting for: domain-certificate issued by Gardener cert-service"
  "certificate not Ready yet"
Root cause (standard_mesh_howto.md §2b + DEPLOYMENT_RECORD): Let's Encrypt DNS-01 challenge record
`_acme-challenge.kcp.api.<DOMAIN>` is a 2-label sub-record the DNS provider REJECTS with
`denied by LocalNamespaceAccessOnly`; also a `*.<DOMAIN>` wildcard SAN cannot cover the 2-label
`kcp.api.<DOMAIN>`, and Certificate.spec.commonName caps at 64 bytes while the domain is 73.
=> DECISION taken previously: MANAGED_TLS=false → STATIC self-signed cert. This blockage is specific to
   the ACME **challenge** sub-records / the kcp.api SAN — normal A-records publish fine.

## Current live TLS: STATIC self-signed `domain-certificate`
Decoded (backup domain-certificate.decoded.txt):
  Issuer: CN=Standard Platform Mesh Local CA ; Subject: CN=ai-trust-1-mesh ; valid Aug-2026 → Nov-2028
  SANs: ai-trust-1.ai-trust.shoot... , *.ai-trust-1.ai-trust.shoot... , kcp.api.ai-trust-1.ai-trust.shoot...
This one secret (platform-mesh-system/domain-certificate) is reused by ALL listeners: terminate,
terminate-wildstar, terminate-aitrust. The MSP operator's ensureWildcardListener/wireIngress
(operator/main.go) attaches every per-instance HTTPRoute to the `terminate-wildstar` listener whose
certificateRefs → domain-certificate. So every instance today serves the self-signed wildcard cert.

## Any leftover traces of the earlier ACME failure?
- The earlier `Certificate domain-certificate` request that timed out (deploy.log/deploy3.log) may still
  exist as a NOT-Ready Certificate object in platform-mesh-system (could not confirm live this session).
  Re-check when login is refreshed: `sk -n platform-mesh-system get certificate domain-certificate`
  and `sk -n platform-mesh-system get certificate,issuer -A`.

## Bottom line for the GOAL
- Managed DNS: fully AVAILABLE (extension healthy, provider openstack-designate, proven live). Adopting
  per-instance managed A-records via annotations/DNSEntry on the shoot's own zone is feasible.
- Managed cert: extension INSTALLED but effectively BLOCKED via the current all-in-one wildcard+kcp.api
  Certificate. A PER-HOST managed cert (single FQDN <id>-<name>.ai-trust-1..., no kcp.api SAN, no wildcard)
  would use a single-label HTTP-01/DNS-01 challenge that has NOT been proven blocked — the block was
  specific to the 2-label `_acme-challenge.kcp.api.*` and the CN>64 / wildcard-SAN constraints. This needs
  a live test once login is refreshed (create ONE per-instance Certificate for a single FQDN and watch it),
  since the FQDN is 63+ chars and may hit CN>64 → SAN-only issuance, plus LE rate limits per instance.

## Verification to run once login refreshed (all read-only)
  sk get crd | grep -E 'dns.gardener.cloud|cert.gardener.cloud'
  sk -n kube-system get cm shoot-info -o jsonpath='{.data.extensions}'
  sk get dnsentry -A ; sk get dnsprovider -A
  sk get certificate -A ; sk get issuer -A
  sk -n platform-mesh-system get certificate domain-certificate -o yaml
  garden get shoot ai-trust-1 -n garden-ai-trust -o jsonpath='{.spec.extensions}{"\n"}{.spec.dns}'
