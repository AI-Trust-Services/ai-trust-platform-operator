# aitrust-operator

Kubernetes controller that watches `Subscription` CRs and provisions isolated AI Trust Platform tenants. One binary, two operating modes driven by the `FEDERATION_MODE` environment variable.

## Modes

| `FEDERATION_MODE` | Role | Watches | Provisions on |
|---|---|---|---|
| `local` (default) | Single-cluster provider | `sub.aitrust.msp/v1alpha1` Subscriptions | Same cluster (in-cluster client) |
| `federated` | Central marketplace controller | `sub.aitrust.remote/v1alpha1` Subscriptions | Payload cluster (mounted SA kubeconfig) |

### Two-client split

Both modes use the same reconciler. `r.Client` always points at the cluster being watched (status writes, finalizer, duplicate guard). `r.remote` is where provisioning happens — identical to `r.Client` in local mode, a separate client built from `REMOTE_KUBECONFIG` in federated mode.

## Reconciliation flow

Each `Subscription` carries a `spec.org` field — the tenant name. The reconciler steps are:

```
1. Finalizer guard          add finalizer on first reconcile; on delete → soft teardown
2. Org validation           empty spec.org → Degraded; duplicate org → Degraded (oldest sub wins)
3. Realm gate (local)       HTTP check against mesh Keycloak; fail-closed on unknown
   Realm gate (federated)   broker Job on Payload creates realm fed-<org> + OIDC IdP; gates on Job success
4. Per-tenant stores Job    Postgres schema + ClickHouse DB + MinIO bucket; durable annotation once done
5. Per-org Secret           oauth2-proxy client secret + cookie secret; idempotent
6. Mesh admin secret copy   copies Keycloak admin creds into provider ns for the Job to use
7. kc-client Job            creates OIDC client in the mesh Keycloak realm
8. oauth2-proxy             Deployment + Service + HTTPRoute + ReferenceGrant
9. OpenFGA admin tuple      seeds platform_administrator role for spec.adminEmail (best-effort)
10. Reciprocal SSO (fed.)   registers OIDC client in Central realm for the browser SSO round-trip
11. Status                  Ready / Provisioning / Degraded / Suspended
```

A `spec.suspended: true` field scales the oauth2-proxy to 0 replicas (login blocked, data intact). All provisioning Jobs are idempotent; the stores Job uses a durable annotation to survive TTL cleanup.

## Tenant naming

| Resource | Local mode | Federated mode |
|---|---|---|
| Keycloak realm | `<org>` | `fed-<org>` |
| Postgres schema | `tenant_<org>` | `tenant_fed_<org>` |
| ClickHouse DB | `tenant_<org>` | `tenant_fed_<org>` |
| MinIO bucket | `tenant-<org>` | `tenant-fed-<org>` |
| oauth2-proxy host | `ai-trust-<org>.<suffix>` | `ai-trust-fed-<org>.<suffix>` |

The `fed-` prefix is applied once (`fedPrefix` global) and flows through every derived name so federated tenants never collide with local ones.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `FEDERATION_MODE` | `local` | `local` or `federated` |
| `PROVIDER_NS` | `aitrust-msp` | Namespace where per-org resources land |
| `INSTANCE_DOMAIN_SUFFIX` | *(long Gardener domain)* | Suffix for per-org hostnames |
| `KC_INTERNAL_URL` | *(in-cluster Keycloak URL)* | Mesh Keycloak internal base URL |
| `KC_PUBLIC_URL` | *(public Keycloak URL)* | Mesh Keycloak public base URL |
| `GATEWAY_NS` | `platform-mesh-system` | Namespace of the Gateway resource |
| `GATEWAY_NAME` | `k8sapi-gateway` | Name of the Gateway resource |
| `OPENFGA_URL` | *(in-cluster OpenFGA URL)* | OpenFGA HTTP endpoint |
| `OPENFGA_STORE_ID` | *(empty)* | OpenFGA store ID for admin tuple seeding |
| `MESH_KC_ADMIN_NS` | `platform-mesh-system` | Namespace of the Keycloak admin secret |
| `MESH_KC_ADMIN_SECRET` | `keycloak-admin` | Name of the Keycloak admin secret |
| `DBMIGRATE_IMAGE` | `mirceacraciun795/aitrust-db-migrate:aitrust` | Postgres migration Job image |
| `CHMIGRATE_IMAGE` | `mirceacraciun795/aitrust-clickhouse-migrate:aitrust` | ClickHouse migration Job image |
| `APP_DB_ROLE` | `ai_trust_app` | Non-superuser Postgres runtime role |
| `REMOTE_KUBECONFIG` | `/etc/a1/kubeconfig` | Payload cluster SA kubeconfig (federated mode only) |
| `PAYLOAD_CLUSTER_NAME` | `ai-trust-1` | Cluster name written to `status.cluster` (federated) |
| `PROD_KC_PUBLIC_URL` | *(Central Keycloak URL)* | Central Keycloak public URL (federated) |
| `IDP_CLIENT_ID` | `aitrust-fed-broker` | OIDC client ID used for the cross-Keycloak IdP |
| `LOCAL_NS` | `aitrust-remote` | Controller's own namespace on Central (federated) |

## Source layout

```
operator/
├── main.go              globals (gvk, finalizer, fedPrefix), embed directive, main()
├── config.go            config struct, cfg(), env()
├── reconciler.go        reconciler struct, Reconcile()
├── secrets.go           ensureOrgSecret, ensureMeshAdminSecret, readMeshAdminCreds, …
├── federation.go        reconcileReciprocalSSO, seedAdminTuple, local Job helpers
├── apply.go             render, applyDoc, jobExists/Succeeded, markProvisioned, deleteOrgResources
├── status.go            setPhase, fail, orgOwner
├── helpers.go           decodeAll, finalizer helpers, strOr/strFrom, dnsSafe, randHex, Keycloak HTTP
├── manifests/           *.tmpl — Job and proxy manifests embedded via embed.FS
├── Makefile             build/test/coverage/docker targets
└── Dockerfile           multi-stage, CGO_ENABLED=0, distroless runtime
```

## Development

```bash
# unit tests (no cluster required)
make test

# unit + integration tests (envtest, no live cluster)
make test-integration

# HTML coverage report
make coverage

# compile binary
make build

# container image
make docker-build IMAGE=my-registry/aitrust-operator IMAGE_TAG=dev

# list all targets
make help
```

### Integration tests

Integration tests use [envtest](https://pkg.go.dev/sigs.k8s.io/controller-runtime/pkg/envtest) and require the CRD at `../charts/aitrust-app/crds/subscription.yaml`. They are gated with `//go:build integration` and run via `make test-integration`.

### E2E tests

End-to-end tests (`e2e/e2e_test.go`) require a live cluster with the full Platform Mesh deployed. See the file header for prerequisites and the `KUBECONFIG`, `KC_ADMIN_*` env vars they accept.

```bash
KUBECONFIG=~/.kube/kind.yaml make test-e2e
```

## Build

The Dockerfile is a two-stage build: Go 1.26 alpine compiles a statically linked binary; the runtime image is `gcr.io/distroless/static:nonroot`. All `*.go` files and `manifests/` are copied in one layer after dependency caching.

```bash
docker build -t aitrust-operator:dev .
```
