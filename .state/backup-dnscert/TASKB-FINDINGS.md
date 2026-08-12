# TASK B — TLS + routing on the mesh gateway today, and what managed-cert-per-host requires
# (READ-ONLY inspection; live cluster UNREACHABLE — garden login expired. Findings from source-of-truth
#  manifests + operator source + external TLS/DNS probes.)
Date: 2026-08-11

## Connectivity
- Garden login EXPIRED: adminkubeconfig request hangs on interactive OIDC (>35s) — needs prerequisites/login.sh.
- No cached shoot-kubeconfig.yaml; cached kcp-admin.kubeconfig points at the shoot tunnel (needs port-forward => needs shoot).
- => Could NOT run live `get k8sapi-gateway -o yaml` / `get secret domain-certificate`. Used repo artifacts + external probes.

## HOW TLS+ROUTING WORKS TODAY (confirmed)
- Gateway: platform-mesh-system/k8sapi-gateway (Gateway API, Traefik). Wildcard listener `terminate-wildstar`,
  hostname `*.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`, port 8443, protocol HTTPS,
  tls.mode=Terminate, tls.certificateRefs -> Secret platform-mesh-system/`domain-certificate`, allowedRoutes.namespaces.from=All.
  (operator ensureWildcardListener reuses the STOCK terminate-wildstar; only creates one if absent — same shape.)
- `domain-certificate` = STATIC SELF-SIGNED. leaf CN=ai-trust-1-mesh, issuer CN=Standard Platform Mesh Local CA
  (self-signed local CA), notBefore Aug10 2026, notAfter Nov12 2028. SAN = apex + `*.ai-trust-1...` + `kcp.api.ai-trust-1...`.
- Per-instance routing: operator (main.go wireIngress) creates, IN platform-mesh-system, per instance:
    HTTPRoute <ns>-app  (path / -> Service oauth2-proxy:8080 in the instance ns)
    HTTPRoute <ns>-keycloak (PathPrefix /keycloak -> Service keycloak:8080)
  both parentRef k8sapi-gateway sectionName=terminate-wildstar, hostnames=[<id>-<name>.<suffix>],
  + a ReferenceGrant in the instance ns allowing the cross-ns backendRef.
- EXTERNAL PROBE (no cluster access): both live hosts (q3c0weh7suf5hgjk-my-aitrust..., 25veqwflh7syq7fm-d...)
  resolve to 130.214.18.166 (shoot-dns wildcard A-record ALREADY published) and serve the self-signed
  CN=ai-trust-1-mesh cert on :443. => DNS is NOT the gap; the TLS TRUST is (browser warning).

## WHAT A MANAGED CERT-PER-HOST REQUIRES IN THE GATEWAY-API/TRAEFIK MODEL (not nginx Ingress)
Key fact: cert.gardener.cloud/purpose:managed + dns.gardener.cloud annotations in the colleague's example are
read off a **networking.k8s.io Ingress** object. THIS SETUP HAS NO INGRESS — it is Gateway API HTTPRoute on Traefik.
shoot-cert-service's Ingress source does NOT watch Gateway/HTTPRoute. So the annotation-on-the-route path (a)
does NOT work here. The two real options:

(b1) PER-INSTANCE MANAGED CERT via a Certificate CR + per-instance listener (recommended, explicit):
  1. Create a `cert.gardener.cloud/v1alpha1 Certificate` CR (namespace platform-mesh-system) with
     spec.commonName/dnsNames=<id>-<name>.<suffix>, spec.secretName=<per-instance-tls>. shoot-cert-service
     issues a real (Let's Encrypt) cert into that Secret. (No annotation-on-Ingress needed.)
  2. Add a per-instance Gateway listener on k8sapi-gateway: name=terminate-<instance>, hostname=<fqdn>,
     port 8443 HTTPS, tls.mode=Terminate, tls.certificateRefs -> the per-instance Secret.
  3. Point the instance HTTPRoutes' parentRefs.sectionName at terminate-<instance> instead of terminate-wildstar.
  DNS: already covered by the existing wildcard A-record; a per-host DNSEntry CR is OPTIONAL (only if you want
  an explicit record). If wanted: `dns.gardener.cloud/v1alpha1 DNSEntry` (dnsName=<fqdn>, targets=LB IP), NOT the
  annotation form.

(b2) ONE managed WILDCARD cert for the whole wildcard listener (simplest, fewest objects):
  - One Certificate CR dnsNames=`*.ai-trust-1...` (+ apex) -> Secret; repoint terminate-wildstar
    tls.certificateRefs to that managed Secret (replace domain-certificate). Covers EVERY instance at once,
    zero per-instance churn, no Let's Encrypt per-host rate-limit risk. LE issues wildcards only via DNS-01,
    which the shoot domain supports (shoot-dns-service is authoritative — wildcard A-record already resolves).

## CONCRETE OBJECT CHANGES (when we DO make changes — this phase makes NONE)
- Annotation path on the route/gateway: NOT supported (no Ingress). Must use Certificate/DNSEntry CRs +
  tls.certificateRefs on a Gateway listener.
- b2 (wildcard, recommended first step): 1 Certificate CR + edit terminate-wildstar certificateRefs. ~2 objects.
- b1 (per-host): per instance = 1 Certificate CR + 1 Gateway listener + repoint 2 HTTPRoutes sectionName;
  operator (wireIngress/ensureWildcardListener) would need to stamp the Certificate + listener too.
- Gateway API on Traefik DOES support multiple HTTPS listeners each with their own certificateRefs (SNI select),
  so both b1 and b2 are viable; b2 is far less churn.

## Backups written to .state/backup-dnscert/
  gateway-listener-patch.tmpl, httproute.tmpl, gardener-managed-dns-cert-reference.md,
  domain-certificate.leaf.crt/.ca.crt/.decoded.txt, operator-wireIngress.snippet.go
