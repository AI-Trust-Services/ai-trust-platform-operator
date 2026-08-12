# Gardener managed DNS + managed TLS via annotations (reference)

A colleague's **working** example on landscape `vv-test.msp01.shoot.gardener.cc-one.showroom.apeirora.eu`
shows the Gardener-native way to get a **public DNS record + a real (managed) certificate** for a host,
purely via annotations — no manual A-record, no manual cert. This is the clean alternative to our current
`Standard_AiTrust_MSP` / `Standard_Platform_Mesh` setup, which uses a shared wildcard listener
(`terminate-wildstar`) + a **static self-signed** cert (we fell back to that because ACME DNS-01 for
`kcp.api.*` was blocked and `knowledge-suite.cloud` wasn't delegated to Gardener).

## The working example (nginx Ingress)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  annotations:
    dns.gardener.cloud/class: garden                     # shoot-dns-service publishes a PUBLIC A-record
    dns.gardener.cloud/dnsnames: whoami.ingress.vv-test.msp01.shoot.gardener.cc-one.showroom.apeirora.eu
    dns.gardener.cloud/ttl: "600"
    cert.gardener.cloud/purpose: managed                 # shoot-cert-service issues a REAL cert into the tls secret
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: whoami.ingress.vv-test.msp01.shoot.gardener.cc-one.showroom.apeirora.eu
      http: { paths: [{ path: /, pathType: Prefix, backend: { service: { name: whoami, port: { number: 80 } } } }] }
  tls:
    - hosts: [whoami.ingress.vv-test.msp01.shoot.gardener.cc-one.showroom.apeirora.eu]
      secretName: whoami-tls-secret
```

## What each annotation does
- `dns.gardener.cloud/class: garden` + `dnsnames: <fqdn>` → **shoot-dns-service** creates a public DNS
  A-record for `<fqdn>` → the ingress/LB IP. (This is the piece our per-instance hosts lacked.)
- `cert.gardener.cloud/purpose: managed` + `tls.secretName` → **shoot-cert-service** issues a managed
  (Let's Encrypt / CA) cert for `<fqdn>` into that secret. (Replaces our static self-signed cert.)

## Why it is NOT a drop-in for our mesh (but IS a good target design)
1. **Different ingress model.** The example uses a classic **nginx Ingress**. Our mesh routes via
   **Gateway API `HTTPRoute` on the Traefik `k8sapi-gateway`**. For us the same annotations must go on a
   **Gateway listener** (for the cert: `cert.gardener.cloud/...` on the Gateway, `tls.certificateRefs` →
   the managed secret) and DNS on the **gateway Service** (`dns.gardener.cloud/dnsnames`) or a `DNSEntry`
   CR — NOT on an Ingress object.
2. **Domain delegation matters.** This works because the host is under the shoot's OWN Gardener-managed
   domain (`*.…shoot.gardener.cc-one…`), where shoot-dns-service is authoritative. Our instance hosts
   (`<id>-<name>.ai-trust-1.ai-trust.shoot.gardener.cc-one…`) ARE under the shoot domain, so the DNS
   annotation should work here too — unlike the earlier `knowledge-suite.cloud` attempt (not delegated →
   "No responsible provider found"; see memory `standard-platform-mesh-ai-trust-1` / the `Gardener_DNS` proof).

## Possible improvement to Standard_AiTrust_MSP (optional, not yet done)
Today: shared wildcard `terminate-wildstar` listener + static self-signed cert → browsers show a cert
warning and the ContentConfiguration had to use in-cluster HTTP (self-signed breaks external-HTTPS verify).
Alternative: per-instance **managed cert** via `cert.gardener.cloud/purpose: managed` on a per-instance
Gateway listener + **managed DNS** via `dns.gardener.cloud/dnsnames` on the gateway Service. Benefit: real
certs (no warning), explicit per-host DNS. Cost: per-instance listener + cert object (more churn on the
shared gateway; watch Let's Encrypt rate limits / the 10-label FQDN limit). Decide before adopting.
