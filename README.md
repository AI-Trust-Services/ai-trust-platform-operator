<p align="center">
  <img alt="AI Trust Platform logo" src="https://ai-trust-services.github.io/logo.svg" width="120"/>
</p>

<h1 align="center">AI Trust Platform Operator</h1>

<p align="center">
  <strong>Multi-tenant Kubernetes operator for the AI Trust Platform.</strong><br/>
  Provision isolated tenants on demand — one shared platform, zero per-tenant infrastructure copies.
</p>

<p align="center">
  <a href="https://api.reuse.software/info/github.com/AI-Trust-Services/ai-trust-platform-operator"><img alt="REUSE status" src="https://api.reuse.software/badge/github.com/AI-Trust-Services/ai-trust-platform-operator"/></a>
  <img alt="License" src="https://img.shields.io/github/license/AI-Trust-Services/ai-trust-platform-operator?style=flat-square"/>
  <img alt="Status" src="https://img.shields.io/badge/status-alpha-orange?style=flat-square"/>
  <img alt="Go version" src="https://img.shields.io/badge/go-1.26-blue?style=flat-square"/>
</p>

---

## About this project

The **AI Trust Platform Operator** is a [controller-runtime](https://github.com/kubernetes-sigs/controller-runtime) based Kubernetes operator that publishes the [AI Trust Platform](https://github.com/AI-Trust-Services/ai-trust-platform) as a **multi-tenant managed service** on top of [KCP](https://github.com/kcp-dev/kcp) and the [ApeiroRA Platform Mesh](https://documentation.apeirora.eu).

A customer clicks **Enable** in the marketplace portal, which creates a `Subscription` custom resource. The operator provisions an **isolated tenant** — a dedicated Keycloak realm, Postgres schema, ClickHouse database, and MinIO bucket — inside **one shared platform instance**. No per-tenant infrastructure copy is created.

The operator ships as a single image and supports two deployment topologies via `FEDERATION_MODE`:

- **`local`** (default) — single-cluster: the marketplace, provider, and app all run on one cluster.
- **`federated`** — cross-cluster: a Central cluster hosts the marketplace and federation controller; tenants are provisioned on a separate Payload cluster.

> ⚠️ This project is currently under active development and is **not intended for production use**. APIs and interfaces are subject to change without prior notice.

---

## Requirements and setup

### Prerequisites

- Kubernetes cluster with [ApeiroRA Platform Mesh](https://documentation.apeirora.eu) installed and Ready
- [KCP](https://github.com/kcp-dev/kcp) provider workspace access
- Tools: `kubectl`, `helm` 3, `docker`, `jq`, `python3`
- Go 1.26+ (only if building the operator from source)

### Install

```bash
# 1. Configure your cluster and registry coordinates
cp prerequisites/config.env.example prerequisites/config.env
# edit prerequisites/config.env

# 2. Run the installer (single-cluster by default)
bash install.sh

# Federated (cross-cluster) mode:
bash install.sh --mode federated
```

The installer runs the full deploy pipeline (`scripts/deploy.sh`, steps 0–7):

| Step | Does |
|------|------|
| `0-check-prerequisites` | tools, cluster reachable, mesh Ready, charts lint, docker login |
| `1-worker-pool` | dedicated node pool for the shared app + operator |
| `2-build-operator-image` | build + push the operator image |
| `2b-build-app-images` | build + push the AI Trust Platform app images |
| `3-provider` | provider workspace + Helm charts + syncagent wiring |
| `3b-shared-app` | deploy the ONE shared multi-tenant AI Trust app |
| `4-consumer-workspace` | org + child account setup |
| `5-bind-apis` | APIBinding to `sub.aitrust.msp` |
| `6-create-subscription` | create a demo `Subscription` |
| `7-verify-portal` | verify portal tile, subscription status, tenant URL |

### Build from source

```bash
cd operator
make build             # compile binary
make test              # unit tests — no cluster required
make test-integration  # envtest-based integration tests
make test-e2e          # E2E against a live cluster (requires KUBECONFIG)
make docker-build      # build container image
```

### Tear down

```bash
bash scripts/reset.sh         # remove subscriptions + shared app + provider (keep the mesh)
bash scripts/reset.sh --pool  # also remove the node pool
```

---

## How it works

Two Helm charts + the shared app + the subscription operator:

| Component | Installed where | Contains |
|-----------|-----------------|----------|
| **`charts/aitrust-app`** (workload) | cluster ns `aitrust-msp` | MT operator, api-syncagent, portal nginx |
| **`charts/aitrust-pm-app`** (kcp) | workspace `root:providers:ai-trust` | APIExport `sub.aitrust.msp`, ContentConfiguration, ProviderMetadata, RBAC |
| **shared app** (`3b-shared-app.sh`) | cluster ns `aitrust-msp` | ONE multi-tenant AI Trust stack (`TENANCY_MODE=jwt`) |

**Tenant provisioning flow:**

```
Portal "Enable"  →  Subscription CR created (kcp)
      │
      ▼
api-syncagent mirrors CR onto the cluster
      │
      ▼
Operator reconciles:
  • derives tenantId from the consumer's kcp logical-cluster id
  • runs one-shot tenant-provision Job → creates per-tenant Keycloak realm
  • provisions Postgres schema + ClickHouse DB + MinIO bucket
  • writes status.url / status.realm / status.tenantId
      │
      ▼
Tenant logs in at their URL; app enforces isolation via realm + schema-per-tenant
```

## The CRD

```yaml
apiVersion: sub.aitrust.msp/v1alpha1
kind: Subscription
metadata: { name: my-subscription }
spec:
  displayName: "My Organisation"
  plan: standard        # standard | enterprise
  adminEmail: you@example.com
# status: { ready, url, tenantId, realm, phase, conditions[] }
```

## Federation (multi-cluster)

In **federated** mode (`--mode federated`) a Central Cluster hosts the marketplace and a Payload Cluster runs the app and tenants. The operator on the Central cluster provisions tenants on the Payload cluster via `REMOTE_KUBECONFIG`.

```bash
bash install.sh --mode federated
# prompts for CENTRAL_KUBECONFIG and PAYLOAD_KUBECONFIG
# or set them as env vars for non-interactive use
```

Required env var in federated mode: `REMOTE_KUBECONFIG` — the operator crashes at startup with a clear message if it is missing.

---

## Support, Feedback, Contributing

This project is open to feature requests, bug reports, and contributions via [GitHub issues](https://github.com/AI-Trust-Services/ai-trust-platform-operator/issues). For contribution guidelines see [CONTRIBUTING.md](CONTRIBUTING.md).

## Security / Disclosure

If you find a security issue, please follow our [security policy](https://github.com/AI-Trust-Services/ai-trust-platform-operator/security/policy). Do not create public GitHub issues for security vulnerabilities.

## Code of Conduct

By participating in this project you agree to abide by our [Code of Conduct](https://github.com/AI-Trust-Services/.github/blob/main/CODE_OF_CONDUCT.md).

## Licensing

Copyright 2026 SAP SE or an SAP affiliate company and ai-trust-platform-operator contributors. Please see our [LICENSE](LICENSE) for copyright and license information. Detailed information including third-party components and their licensing is available [via the REUSE tool](https://api.reuse.software/info/github.com/AI-Trust-Services/ai-trust-platform-operator).

<p align="center"><img alt="Bundesministerium für Wirtschaft und Klimaschutz (BMWK)-EU funding logo" src="https://apeirora.eu/assets/img/BMWK-EU.png" width="400"/></p>
