# AI Trust Platform — how-to (login → deploy → Enable → subscribe → tenant login)

A short operator how-to for the **multi-tenant** MSP provider. It publishes ONE shared AI Trust app and,
per customer **Subscription**, provisions a **tenant** (a per-tenant Keycloak realm + `tenant_id` data
isolation) inside that shared app — no app copy per customer. Read alongside `README.md`.

## 0. One-time
Refresh the Gardener login (Ubuntu terminal — the bare token expires):
```bash
bash prerequisites/login.sh
```
Everything is driven by `prerequisites/config.env` (workspace, namespace, API group, worker pool, hosts,
image tags). Do not hardcode — edit `config.env` if a name must change.

## 1. Deploy (one click)
```bash
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash \
  '/mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP/scripts/deploy.sh'
```
`deploy.sh` runs, in order: `0-check → 1-worker-pool → 2-build-operator-image → 2b-build-app-images →
3-provider → 3b-shared-app → 4-consumer-workspace → 5-bind-apis → 6-create-subscription → 7-verify-portal`.

What each phase gives you:
- **1** adds the `ai-trust` worker pool (`m_c16_m128_v2`, ~10 min to a Ready node).
- **2 / 2b** build+push the operator (`aitrust-operator:v1`) and the MT app images (tag `aitrust`,
  including `aitrust-keycloak-provision` — the operator's tenant-provision Job image).
- **3** registers the provider (APIExport `sub.aitrust.msp` publishing `subscriptions`).
- **3b** deploys the ONE shared app at `SHARED_APP_HOST` (`TENANCY_MODE=jwt`, Postgres RLS app role).
- **4/5** create the demo org + account and bind the API (the scripted "Enable").
- **6** creates a demo `Subscription`; **7** waits for it to be Ready and prints the tenant URL + realm.

## 2. Enable (in the portal, the real customer path)
Open the portal root, go to your **account → Namespaces → default**, expand the **"AI Trust Platform"**
tile category, and click **Enable**. Under the hood this creates the APIBinding to `sub.aitrust.msp`
(step 5 does the same non-interactively).

## 3. Create a Subscription
In the same tile, click **Create** and fill the form (Name, Display Name, Plan, Admin Email). This writes a
`Subscription` CR:
```yaml
apiVersion: sub.aitrust.msp/v1alpha1
kind: Subscription
metadata: { name: my-subscription }
spec:
  displayName: "AI Trust MT — tenant"
  plan: standard          # standard | enterprise
  adminEmail: you@example.com
```
The syncagent mirrors it to the shoot; the MT operator provisions a per-tenant realm `t-<tenantId>` in the
shared Keycloak (~1-2 min). Watch it flip:
```
phase=Provisioning ready=<no> …
phase=Ready ready=true url=https://<tenantId>-my-subscription.<shared-suffix> realm=t-<tenantId>
```

## 4. Tenant logs into the shared app with its own realm
Open the **URL column** value (`status.url`) shown in the portal / printed by step 7. It routes to the ONE
shared app (`SHARED_APP_HOST`); the app resolves the tenant from the realm's `tenant_id` token claim, so:
- the tenant authenticates against **its own realm** `t-<tenantId>` (not the mesh/portal Dex, and not any
  other tenant's realm),
- every read/write is scoped to `tenant_id` by Postgres **RLS** + per-tenant ClickHouse/MinIO prefixing.
Two different subscriptions see completely separate data on the same deployment.

## 5. Teardown
```bash
bash scripts/reset.sh          # delete subscriptions + shared app + provider (mesh untouched)
bash scripts/reset.sh --pool   # also drop the ai-trust worker pool
```
Deleting a `Subscription` soft-disables its tenant realm; the append-only inference log is never deleted.

## Notes
- Isolated from `../Standard_AiTrust_MSP`: different group / ws / ns / pool / image tag — run both at once.
- Reused mesh fixes: KCP `:8443`, PM-chart-before-workload, syncagent hostAlias, `bind_authenticated`,
  ContentConfiguration over in-cluster HTTP. See `README.md` and `../Standard_MSP_Demo`.
