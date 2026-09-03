#!/bin/bash
# 3b-shared-app.sh — deploy the ONE SHARED "AI Trust Platform" app (multi-tenant) into the provider
# namespace on the ai-trust worker pool. Subscriptions (each a tenant) attach to THIS instance — the
# operator never stamps another copy. Renders the gold app manifests (config/k8s-app/*) with the MT
# overlay: TENANCY_MODE=jwt, a non-superuser app DB role for RLS, one shared host.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; [ -s "$KUBECONFIG" ] || mint_shoot_kubeconfig
sk() { kubectl "$@" 2>&1 | grep -avi memcache; }

NS="$PROVIDER_NS"
URL="https://$SHARED_APP_HOST"
GOLD="$BUNDLE/config/k8s-app"
OVER="$BUNDLE/config/shared-app"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
COOKIE="$(head -c16 /dev/urandom | xxd -p)"

# Strong non-default credentials. The MT app's tenancy security preflight (libs/tenancy
# security_preflight.py) REFUSES to boot any backend when TENANCY_MODE=jwt if a known-default secret
# (POSTGRES_PASSWORD=postgres, MINIO_ROOT_PASSWORD=minioadmin, APP_ADMIN_PASSWORD=password,
# KEYCLOAK_ADMIN_PASSWORD=admin, RABBITMQ_PASSWORD=guest) is still present. Generate strong values once
# and persist them in .state so re-runs reuse the SAME creds (idempotent; stores keep their init creds).
SECRETS_ENV="$STATE/mt-secrets.env"
gen_secret(){ head -c18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c24; }
if [ -f "$SECRETS_ENV" ]; then
  set -a; source "$SECRETS_ENV"; set +a
  log "Reusing persisted MT credentials ($SECRETS_ENV)"
else
  MT_POSTGRES_PASSWORD="$(gen_secret)"; MT_APP_DB_PASSWORD="$(gen_secret)"
  MT_RABBITMQ_PASSWORD="$(gen_secret)"; MT_MINIO_ROOT_PASSWORD="$(gen_secret)"
  MT_KEYCLOAK_ADMIN_PASSWORD="$(gen_secret)"; MT_APP_ADMIN_PASSWORD="$(gen_secret)"
  cat > "$SECRETS_ENV" <<EOF
MT_POSTGRES_PASSWORD=$MT_POSTGRES_PASSWORD
MT_APP_DB_PASSWORD=$MT_APP_DB_PASSWORD
MT_RABBITMQ_PASSWORD=$MT_RABBITMQ_PASSWORD
MT_MINIO_ROOT_PASSWORD=$MT_MINIO_ROOT_PASSWORD
MT_KEYCLOAK_ADMIN_PASSWORD=$MT_KEYCLOAK_ADMIN_PASSWORD
MT_APP_ADMIN_PASSWORD=$MT_APP_ADMIN_PASSWORD
EOF
  chmod 600 "$SECRETS_ENV"
  log "Generated strong MT credentials → $SECRETS_ENV (gitignored)"
fi

log "Rendering shared MT app into ns '$NS' at $URL …"
render() {  # swap the app ns + URL placeholders + image registry/tag + strong creds
  sed -e "s|ai-trust-app|$NS|g" \
      -e "s|__APP_NS__|$NS|g" \
      -e "s|__APP_URL__|$URL|g" \
      -e "s|__APP_DOMAIN__|$SHARED_APP_HOST|g" \
      -e "s|__COOKIE_SECRET__|$COOKIE|g" \
      -e "s|__POSTGRES_PASSWORD__|$MT_POSTGRES_PASSWORD|g" \
      -e "s|__APP_DB_PASSWORD__|$MT_APP_DB_PASSWORD|g" \
      -e "s|__RABBITMQ_PASSWORD__|$MT_RABBITMQ_PASSWORD|g" \
      -e "s|__MINIO_ROOT_PASSWORD__|$MT_MINIO_ROOT_PASSWORD|g" \
      -e "s|__KEYCLOAK_ADMIN_PASSWORD__|$MT_KEYCLOAK_ADMIN_PASSWORD|g" \
      -e "s|__APP_ADMIN_PASSWORD__|$MT_APP_ADMIN_PASSWORD|g" \
      -e "s|image: aitrust/\([a-z0-9-]*\):kind|image: $REGISTRY/aitrust-\1:$TAG|g" "$1"
}

# 1) namespace + configmaps (use the MT pg-init that creates the RLS app role) + MT secret/config
render "$GOLD/00-namespace.yaml"        > "$OUT/00.yaml"
render "$GOLD/01-cm-ch-config.yaml"     > "$OUT/01a.yaml"
render "$GOLD/01-cm-otelcol.yaml"       > "$OUT/01b.yaml"
render "$OVER/01-cm-pg-init-mt.yaml"    > "$OUT/01c.yaml"   # MT: pg-init creates ai_trust_app role
render "$OVER/02-secret-config-mt.tmpl" > "$OUT/02.yaml"    # MT: TENANCY_MODE=jwt + APP_DATABASE_URL
render "$GOLD/10-infra.yaml"            > "$OUT/10.yaml"
render "$GOLD/20-jobs.yaml"             > "$OUT/20.yaml"
render "$GOLD/30-app.yaml"              > "$OUT/30.yaml"
render "$GOLD/40-workers-shell-proxy.yaml" > "$OUT/40.yaml"

log "Applying namespace + config …"
sk apply -f "$OUT/00.yaml"
sk -n "$NS" apply -f "$OUT/01a.yaml" -f "$OUT/01b.yaml" -f "$OUT/01c.yaml" -f "$OUT/02.yaml"

# 0a) MESH admin secret for per-tenant user management. The users-backend (MT/jwt mode) manages users in
#     each tenant's realm using the mesh Keycloak bootstrap admin (same creds the operator/kc-client Job
#     use). The operator also copies this on Subscription reconcile (ensureMeshAdminSecret), but the shared
#     app can be deployed BEFORE any Subscription exists — so copy it here too, idempotently, or the
#     users-backend pod crash-loops on the missing secretKeyRef. Source: mesh ns keycloak-admin.
if ! sk -n "$NS" get secret mesh-keycloak-admin >/dev/null 2>&1; then
  MESH_ADMIN_NS="${MESH_ADMIN_NS:-$MESH_NS}"; MESH_ADMIN_SECRET="${MESH_ADMIN_SECRET:-keycloak-admin}"
  MU="$(sk -n "$MESH_ADMIN_NS" get secret "$MESH_ADMIN_SECRET" -o jsonpath='{.data.username}' 2>/dev/null)"
  MP="$(sk -n "$MESH_ADMIN_NS" get secret "$MESH_ADMIN_SECRET" -o jsonpath='{.data.password}' 2>/dev/null)"
  if [ -n "$MU" ] && [ -n "$MP" ]; then
    cat <<EOF | sk apply -f -
apiVersion: v1
kind: Secret
metadata: { name: mesh-keycloak-admin, namespace: $NS, labels: { app.kubernetes.io/managed-by: aitrust-shared-app } }
type: Opaque
data: { username: "$MU", password: "$MP" }
EOF
    ok "copied mesh-keycloak-admin into $NS (for per-tenant user management)"
  else
    warn "mesh admin secret $MESH_ADMIN_NS/$MESH_ADMIN_SECRET not found — users-backend will not start until it exists (operator copies it on first Subscription)"
  fi
fi

log "Applying infra (postgres/clickhouse/minio/rabbitmq/keycloak) + waiting …"
sk -n "$NS" apply -f "$OUT/10.yaml"
sk -n "$NS" rollout status deploy/postgres --timeout=180s || true
sk -n "$NS" rollout status deploy/keycloak --timeout=180s || true

log "Running one-shot jobs (db-migrate/clickhouse-migrate/keycloak-provision/minio-init) …"
sk -n "$NS" apply -f "$OUT/20.yaml"
# db-migrate runs as OWNER (postgres) via DATABASE_URL — creates schema + RLS; the app role can then use it.

# 1a) GRANT-RECONCILE (durability): re-assert the runtime app-role grants on EVERY table/sequence AFTER
#     migrations. pg-init's ALTER DEFAULT PRIVILEGES only covers tables created after it ran, so a table
#     created by a later db-migrate (or on a DB with inconsistent history) can end up ungranted → the app
#     500s with "relation X does not exist / permission denied". This idempotent pass closes that gap so a
#     freshly provisioned tenant/deploy is never missing access. Waits for db-migrate to finish first.
log "Reconciling ai_trust_app grants on all tables (post-migrate, idempotent) …"
sk -n "$NS" wait --for=condition=complete job/db-migrate --timeout=240s >/dev/null 2>&1 || true
PGPOD="$(sk -n "$NS" get pods --no-headers 2>/dev/null | grep -E '^postgres' | awk '{print $1}' | head -1)"
if [ -n "$PGPOD" ]; then
  sk -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -v ON_ERROR_STOP=1 -U $POSTGRES_USER -d $POSTGRES_DB <<SQL
GRANT USAGE ON SCHEMA public TO ai_trust_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ai_trust_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ai_trust_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ai_trust_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ai_trust_app;
SQL' 2>&1 | grep -avi memcache || warn "grant-reconcile skipped (postgres not ready?)"
  ok "app-role grants reconciled"
fi

log "Applying app backends + frontends + workers + shell + oauth2-proxy …"
sk -n "$NS" apply -f "$OUT/30.yaml" -f "$OUT/40.yaml"

# 1b) ROLES → MESH OpenFGA: seed the app's authorization model + built-in role tuples into ONE app store
#     "ai-trust" in the SHARED mesh OpenFGA (see docs/mesh-idp-integration-design.md ADDENDUM 2). The app
#     backends read the resolved store id from OPENFGA_STORE_ID env. Data isolation stays via Postgres RLS.
OPENFGA_MESH_URL="${OPENFGA_MESH_URL:-http://openfga.$MESH_NS.svc.cluster.local:8080}"
OPENFGA_STORE_NAME="${OPENFGA_STORE_NAME:-aitrust}"
ADMIN_USER="$(sk -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_ADMIN_USERNAME}' | base64 -d 2>/dev/null || echo admin)"
log "Seeding app roles into the MESH OpenFGA (store '$OPENFGA_STORE_NAME' @ $OPENFGA_MESH_URL) …"
sk -n "$NS" delete job openfga-provision --ignore-not-found >/dev/null 2>&1
cat <<EOF | sk apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: openfga-provision, namespace: $NS }
spec:
  backoffLimit: 6
  template:
    metadata: { labels: { app: openfga-provision } }
    spec:
      restartPolicy: OnFailure
      nodeSelector: { workload: $MSP_WORKER_LABEL }
      tolerations: [{ key: workload, value: $MSP_WORKER_LABEL, effect: NoSchedule }]
      containers:
        - name: openfga-provision
          image: $REGISTRY/aitrust-openfga-provision:$TAG
          imagePullPolicy: Always
          env:
            - { name: OPENFGA_URL, value: "$OPENFGA_MESH_URL" }
            - { name: OPENFGA_STORE_NAME, value: "$OPENFGA_STORE_NAME" }
            - { name: INITIAL_ADMIN_USER, value: "$ADMIN_USER" }
            - { name: OPENFGA_STORE_ID_FILE, value: "/tmp/store_id" }
EOF
sk -n "$NS" wait --for=condition=complete job/openfga-provision --timeout=180s || warn "openfga-provision job not complete yet"
# resolve the store id the provisioner created — paginate + EXACT name match (jq-free via python).
# NOTE the provisioner creates the store under $OPENFGA_STORE_NAME; the mesh OpenFGA holds many stores
# so a single unpaginated page + loose grep can miss it (that shipped __OPENFGA_STORE_ID__ once).
STORE_ID="$(sk -n "$NS" run fgaid-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s '$OPENFGA_MESH_URL/stores?page_size=200'" 2>/dev/null \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(next((s['id'] for s in d.get('stores',[]) if s.get('name')=='$OPENFGA_STORE_NAME'),''))" 2>/dev/null)"
if [ -n "$STORE_ID" ]; then
  ok "app OpenFGA store '$OPENFGA_STORE_NAME' id = $STORE_ID"
  log "Setting OPENFGA_URL + OPENFGA_STORE_ID on all backends + the operator …"
  # backends AND the operator need it (operator's seedAdminTuple skips silently if storeID is empty)
  for d in $(sk -n "$NS" get deploy -o name | grep -E 'backend|aitrust-operator|policy-checker|otel-clickhouse-consumer'); do
    sk -n "$NS" set env "$d" OPENFGA_URL="$OPENFGA_MESH_URL" OPENFGA_STORE_ID="$STORE_ID" >/dev/null || true
  done
else
  warn "could not resolve the OpenFGA store id — backends + operator will fail authz until OPENFGA_STORE_ID is set (nav shows only Overview; seedAdminTuple skipped). Check the openfga-provision job logs + store name '$OPENFGA_STORE_NAME'."
fi

# 2) RLS wiring: the runtime backends + workers must connect as the NON-SUPERUSER app role so RLS bites.
#    Point their DATABASE_URL at APP_DATABASE_URL (db-migrate Job keeps the owner URL — it already ran).
log "Pointing runtime backends/workers at the RLS app role (APP_DATABASE_URL) …"
for d in $(sk -n "$NS" get deploy -o name | grep -E 'backend|worker|otel-clickhouse-consumer|otel-rmq-bridge' ); do
  sk -n "$NS" set env "$d" DATABASE_URL="$(sk -n "$NS" get secret app-secrets -o jsonpath='{.data.APP_DATABASE_URL}' | base64 -d)" >/dev/null || true
done

# 3) pin everything to the ai-trust worker pool
log "Pinning the shared app to the '$MSP_WORKER_LABEL' worker pool …"
for d in $(sk -n "$NS" get deploy -o name); do
  sk -n "$NS" patch "$d" --type=strategic -p \
    "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"workload\":\"$MSP_WORKER_LABEL\"},\"tolerations\":[{\"key\":\"workload\",\"value\":\"$MSP_WORKER_LABEL\",\"effect\":\"NoSchedule\"}]}}}}" >/dev/null || true
done

# 4) ingress: one HTTPRoute for the shared host (+ /keycloak) → oauth2-proxy, on the mesh wildcard listener.
log "Wiring ingress for $SHARED_APP_HOST …"
cat <<EOF | sk apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: aitrust-shared-app, namespace: $GATEWAY_NS }
spec:
  parentRefs: [{ name: $GATEWAY_NAME, namespace: $GATEWAY_NS, sectionName: terminate-wildstar }]
  hostnames: ["$SHARED_APP_HOST"]
  rules:
  - backendRefs: [{ group: "", kind: Service, name: oauth2-proxy, namespace: $NS, port: 8080 }]
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata: { name: allow-gw-to-aitrust, namespace: $NS }
spec:
  from: [{ group: gateway.networking.k8s.io, kind: HTTPRoute, namespace: $GATEWAY_NS }]
  to: [{ group: "", kind: Service }]
EOF

ok "Shared MT app deployed in ns '$NS' at $URL (backends on RLS role, pinned to $WORKER_POOL)."
log "Subscriptions (tenants) attach to THIS instance — the operator provisions per-tenant realms, no new copies."
