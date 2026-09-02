# AI Trust Platform — Claude Code context

## Project layout

```
operator/       Go source for the aitrust-operator (main reconciler)
charts/         Helm charts (aitrust-app, aitrust-pm-app)
config/         Shared-app manifests and secret templates
crds/           Kubernetes CRD definitions
scripts/        Deploy pipeline shell scripts (1-provider.sh … 6-create-subscription.sh)
install.sh      Install entry point — supports both single-cluster and federated mode (--mode local|federated)
```

## Build and test (run from operator/)

```sh
make build             # compile binary
make test              # unit tests — no cluster needed
make test-integration  # envtest-based integration tests — no cluster needed
make test-e2e          # E2E against a live cluster (requires KUBECONFIG)
make coverage          # unit + integration with HTML coverage report
make lint              # golangci-lint
make docker-build      # build container image (IMAGE / IMAGE_TAG vars)
```

Go version: **1.26**

## Operator modes (FEDERATION_MODE)

The operator ships as one image with two runtime modes controlled by `FEDERATION_MODE`:

| Value | Behaviour |
|-------|-----------|
| `local` (default) | Single-cluster — provisions in-cluster, direct-HTTP realm gate |
| `federated` | Cross-cluster — provisions on payload cluster via `REMOTE_KUBECONFIG`, broker-trust realm gate |

## Required env vars (fail-fast at startup)

The operator crashes immediately on startup with a clear message if these are unset:

| Var | When required |
|-----|---------------|
| `OPENFGA_STORE_ID` | Always |
| `REMOTE_KUBECONFIG` | Only when `FEDERATION_MODE=federated` |

All other vars have sensible defaults — see `operator/config.go` for the full list.

## Conventions

- **Fail-fast env vars:** use `mustEnv(k)` for vars that have no safe default. Use `env(k, default)` for optional vars.
- **Do not hand-edit** FGA schema files — they are seeded by the `openfga-provision-job` at deploy time.
- **Do not commit** `.env` files or `.state/` directories (contain generated secrets).
- Image tags in `charts/aitrust-app/values.yaml` are Docker build numbers (v21, …), independent of the semantic release version in `CHANGELOG.md`.
