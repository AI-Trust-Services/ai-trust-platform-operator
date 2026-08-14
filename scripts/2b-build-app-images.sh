#!/bin/bash
# 2b-build-app-images.sh — build + push the MT APP images from the AUTHORITATIVE GIT REPO
# (AI-Trust-Services/ai-trust-platform), NOT the stale local checkout. The git repo has the full
# authorization stack (users service, libs/authorization, openfga-provision, custom roles) that the
# local copy lacks. These images are what the ONE SHARED app (3b-shared-app.sh) runs.
#
# MT differences vs the standalone build:
#   (a) tag = $TAG (aitrust-mt), distinct from the single-tenant aitrust-1 build;
#   (b) shell viewUrls are already RELATIVE in the app code — no sed host hack;
#   (c) ALSO build+push: users-backend/users-frontend (IAM/roles), openfga-provision (seeds the app's
#       roles → OpenFGA), keycloak-provision. openfga-provision is the operator's OPENFGA_PROVISION_IMAGE.
# Frontends baked with PUB=$SHARED_APP_HOST. --skip-build to only retag+push. --skip-clone to reuse the clone.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$HERE/lib.sh"; load_config
PUB="https://$SHARED_APP_HOST"

: "${APP_GIT_URL:=https://github.com/AI-Trust-Services/ai-trust-platform.git}"
: "${APP_GIT_REF:=main}"
SRC="$BUNDLE/../ai-trust-platform-git"   # bundle-managed clone (the source of truth for installs)

SKIP_BUILD=0; SKIP_CLONE=0
for a in "$@"; do [ "$a" = "--skip-build" ] && SKIP_BUILD=1; [ "$a" = "--skip-clone" ] && SKIP_CLONE=1; done

if [ "$SKIP_CLONE" -eq 0 ]; then
  if [ -d "$SRC/.git" ]; then
    log "Updating app git clone ($SRC) to $APP_GIT_REF…"
    git -C "$SRC" fetch --depth 1 origin "$APP_GIT_REF" >/dev/null 2>&1 && git -C "$SRC" reset --hard FETCH_HEAD >/dev/null 2>&1 \
      || die "git update failed in $SRC"
  else
    log "Cloning $APP_GIT_URL@$APP_GIT_REF → $SRC…"
    git clone --depth 1 --branch "$APP_GIT_REF" "$APP_GIT_URL" "$SRC" >/dev/null 2>&1 || die "git clone failed"
  fi
fi
[ -d "$SRC/libs/authorization" ] || die "clone missing libs/authorization — is $APP_GIT_REF the right ref? (this is the whole point: build from git, which HAS the roles module)"
COMMIT="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)"
ok "app source = git $APP_GIT_REF @ $COMMIT (has authorization module)"

BACKENDS="ai-system-registry monitoring overview alerts compliance decision-trace-analyzer users"
FRONTENDS="ai-system-registry monitoring overview alerts compliance decision-trace-analyzer users"
if [ "$SKIP_BUILD" -eq 0 ]; then
  log "Building MT app images from $SRC (PUB=$PUB, tag=$TAG)…"
  cd "$SRC"
  for c in $BACKENDS; do docker build -q -t aitrust/$c-backend:build -f $c/backend/Dockerfile . >/dev/null; done
  docker build -q -t aitrust/db-migrate:build ./libs/persistence >/dev/null   # git Dockerfile: COPY . . from the libs/persistence context
  docker build -q -t aitrust/clickhouse-migrate:build ./libs/clickhouse >/dev/null
  docker build -q -t aitrust/keycloak-provision:build ./infra/keycloak >/dev/null
  docker build -q -t aitrust/openfga-provision:build -f infra/openfga-provision/Dockerfile . >/dev/null   # repo-root ctx (COPYs libs/authorization)
  docker build -q -t aitrust/policy-checker-worker:build -f policy-checker-worker/Dockerfile . >/dev/null
  docker build -q -t aitrust/clickhouse-consumer:build -f consumers/clickhouse-consumer/Dockerfile . >/dev/null
  docker build -q -t aitrust/rmq-bridge:build ./otel-pipeline/rmq-bridge >/dev/null
  docker build -q -t aitrust/shell:build ./shell >/dev/null
  # frontends (VITE_* baked). users frontend = the IAM/Role-Management MFE.
  docker build -q -t aitrust/ai-system-registry-frontend:build --build-arg VITE_REGISTRY_API_BASE=/api/registry/v1 ./ai-system-registry/frontend >/dev/null
  docker build -q -t aitrust/monitoring-frontend:build --build-arg VITE_MONITORING_API_BASE=/api/monitoring/v1 ./monitoring/frontend >/dev/null
  docker build -q -t aitrust/alerts-frontend:build --build-arg VITE_ALERTS_API_BASE=/api/alerts/v1 --build-arg VITE_ALERTS_URL=$PUB/alerts ./alerts/frontend >/dev/null
  docker build -q -t aitrust/compliance-frontend:build --build-arg VITE_COMPLIANCE_API_BASE=/api/compliance/v1 --build-arg VITE_REGISTRY_API_BASE=/api/registry/v1 ./compliance/frontend >/dev/null
  docker build -q -t aitrust/decision-trace-analyzer-frontend:build --build-arg VITE_DTA_API_BASE=/api/dta/v1 ./decision-trace-analyzer/frontend >/dev/null
  docker build -q -t aitrust/overview-frontend:build --build-arg VITE_OVERVIEW_API_BASE=/api/overview/v1 --build-arg VITE_ALERTS_API_BASE=/api/alerts/v1 --build-arg VITE_ALERTS_URL=$PUB/alerts --build-arg VITE_REGISTRY_URL=$PUB/registry --build-arg VITE_COMPLIANCE_URL=$PUB/compliance --build-arg VITE_COMPLIANCE_API_BASE=/api/compliance/v1 --build-arg VITE_USERS_API_BASE=/api/users/v1 ./overview/frontend >/dev/null
  docker build -q -t aitrust/users-frontend:build --build-arg VITE_USERS_API_BASE=/api/users/v1 ./users/frontend >/dev/null
  ok "images built"
fi

log "Retag + push to $REGISTRY:$TAG…"
push(){ local local_tag=$1 remote=$2; docker tag "$local_tag" "$remote"; docker push -q "$remote" >/dev/null && echo "  pushed $remote"; }
for c in $BACKENDS; do push aitrust/$c-backend:build $REGISTRY/aitrust-$c-backend:$TAG; done
for c in $FRONTENDS; do push aitrust/$c-frontend:build $REGISTRY/aitrust-$c-frontend:$TAG; done
for c in db-migrate clickhouse-migrate keycloak-provision openfga-provision policy-checker-worker clickhouse-consumer rmq-bridge shell; do push aitrust/$c:build $REGISTRY/aitrust-$c:$TAG; done
ok "all MT app images pushed to $REGISTRY (tag $TAG) from git @ $COMMIT — incl users (IAM) + openfga-provision (roles)"
