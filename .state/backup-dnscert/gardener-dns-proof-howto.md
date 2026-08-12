# Gardener DNS — how it works, and how we use it (deep dive)

Audience: a developer who wants to understand *why* the one-click test works and how the mesh
phase will reuse it. Nothing here is AI-Trust-specific — it's stock Gardener DNS.

> **KEY FINDING (validated live 2026-08-10 on `ai-trust-1`).**
> The zone **`knowledge-suite.cloud` is NOT delegated to Gardener** on this landscape — a `DNSEntry`
> for it fails with `state: Error — "No responsible provider found"`. (Same on the older `ccep6xjste`
> cluster, which is why that setup used manual A-records.)
> **BUT** the shoot's **own Gardener domain** is fully auto-managed: a `DNSEntry` for
> `*.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu` goes **`Ready`** (provider
> `openstack-designate`) and resolves publicly. **Gardener cert-service** (`certificates.cert.gardener.cloud`)
> is also present, so TLS for that domain can be auto-issued.
> **Decision:** the Standard Platform Mesh install uses a host under the Gardener domain
> (`st-mesh.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`) — DNS **and** TLS fully
> Gardener-managed, no external DNS, no custom wildcard cert.

---

## 1. The mechanism: `shoot-dns-service`

Gardener ships an optional extension, **`shoot-dns-service`**. When it's enabled on a shoot
(it is on `ai-trust-1` — `spec.extensions[].type: shoot-dns-service`), Gardener runs a DNS
controller that watches for two kinds of requests inside the shoot and reconciles them into
**real records at the backing DNS provider** for the shoot's delegated zone(s):

1. **`DNSEntry` custom resources** (`dns.gardener.cloud/v1alpha1`) — an explicit, self-contained
   record request. This is what our test uses because it's the most direct proof.
2. **Annotations on `Service` / `Ingress` / `Gateway` resources** — the ergonomic path for real
   workloads. You annotate the object and Gardener derives the record from it.

Either way the record is **published publicly** (subject to the parent zone being delegated to
Gardener's DNS provider), so it resolves from anywhere — not just inside the cluster.

---

## 2. What the test creates (`DNSEntry`)

```yaml
apiVersion: dns.gardener.cloud/v1alpha1
kind: DNSEntry
metadata:
  name: dns-test-st-mesh
  namespace: default
  annotations:
    dns.gardener.cloud/class: garden     # tells the Gardener DNS controller to handle it
spec:
  dnsName: "st-mesh-dnstest.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
  ttl: 120
  targets:
    - "<ip>"                             # a real LB IP if present, else a placeholder
```

`deploy-dns-test.sh` applies this, then waits for **`status.state: Ready`** (Gardener accepted
and pushed the record), then independently checks the name **resolves publicly** from the WSL host.

The `class: garden` annotation is the switch that hands the entry to Gardener's controller. Without
it the entry is ignored.

---

## 3. How the mesh phase reuses this (annotation path)

The Platform Mesh gateway is exposed by a `Service` of type `LoadBalancer` (Traefik). Instead of a
standalone `DNSEntry`, the mesh phase annotates **that Service** so Gardener creates the record
pointing at the LB automatically:

```yaml
metadata:
  annotations:
    dns.gardener.cloud/class: garden
    dns.gardener.cloud/dnsnames: st-mesh.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
    dns.gardener.cloud/ttl: "120"
```

Gardener reads the Service's assigned LoadBalancer IP and publishes
`st-mesh.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu → <LB IP>` — no manual
A-record, no separate DNSEntry. Gardener cert-service issues the matching TLS cert. This is why
we prove the DNSEntry path first: it's the same controller and the same zone, just triggered
explicitly, so a PASS here means the annotation path will work for the mesh.

`DNSEntry` vs annotations — same result, different trigger:
- **DNSEntry**: explicit, decoupled from any workload. Best for tests / static records.
- **Annotations**: automatic, tied to a Service/Gateway's lifecycle + its LB IP. Best for the mesh.

---

## 4. Prerequisites & assumptions

- **Extension enabled**: `shoot-dns-service` on the shoot (verified on `ai-trust-1`).
- **Zone delegation**: the parent zone `knowledge-suite.cloud` must be served by a DNS provider that
  Gardener manages for this project (a `DNSProvider` / the project's default provider). If the zone
  is *not* delegated to Gardener, the `DNSEntry` may still go `Ready` in-cluster but won't resolve
  publicly — that's the one thing the resolution check catches. If that happens, use a manual
  A-record at wherever `knowledge-suite.cloud` is actually hosted (the script prints the IP).
- **Auth**: garden OIDC via `login.sh`, then a minted 4 h shoot admin kubeconfig.

---

## 5. Troubleshooting

| Symptom | Check |
|---|---|
| `DNSEntry CRD not found` | `shoot-dns-service` isn't exposing in-cluster DNSEntry here — use the Service/Gateway annotation path, or manual DNS. |
| `state` stuck `Pending` / `Error` | `kubectl -n default get dnsentry dns-test-st-mesh -o yaml` → read `status.message`. Common: no `DNSProvider` for the zone, or the zone isn't delegated to Gardener. |
| `Ready` but not resolvable publicly | Propagation lag (wait a few min) **or** the parent zone isn't delegated to Gardener's provider → the record exists in Gardener's view but the world queries a different authoritative server. Verify who is authoritative for `knowledge-suite.cloud`. |
| `adminkubeconfig failed` | Garden OIDC session expired → re-run `prerequisites/login.sh` in the Ubuntu terminal. |

## 6. Cleanup
`scripts/reset.sh` deletes the `DNSEntry`; Gardener withdraws the public record shortly after.
Nothing else on the shoot is modified by this bundle.
