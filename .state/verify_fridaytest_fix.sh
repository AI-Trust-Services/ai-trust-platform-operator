#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== kc-client-fridaytest Job final status ====="
kubectl -n "$NS" get job kc-client-fridaytest --no-headers 2>&1 | f
kubectl -n "$NS" logs job/kc-client-fridaytest --tail=6 2>&1 | f | tail -6

echo; echo "===== verify the fridaytest client now has post.logout.redirect.uris ====="
KCU=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.username}' | base64 -d)
KCP=$(kubectl -n "$NS" get secret mesh-keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
INNER='K=/opt/keycloak/bin/kcadm.sh
$K config credentials --server http://localhost:8080/keycloak --realm master --user "$U" --password "$P" >/dev/null 2>&1
CID=$($K get clients -r fridaytest -q clientId=aitrust-mt-app --fields id --format csv --noquotes 2>/dev/null | head -1)
echo "  client id: $CID"
$K get clients/$CID -r fridaytest --fields clientId,redirectUris,attributes 2>/dev/null'
kubectl -n platform-mesh-system exec -i keycloak-0 -- env U="$KCU" P="$KCP" sh -c "$INNER" 2>&1 | f

echo; echo "===== verify users-backend can list users in the fridaytest realm (tenant-aware) ====="
echo "  simulate a fridaytest request: needs the tenant in context, which comes from a real JWT."
echo "  Instead, confirm the backend boots clean with mesh admin creds (no 'misconfigured' error):"
kubectl -n "$NS" logs deploy/users-backend --tail=20 2>&1 | f | grep -iE 'error|misconfigured|MESH_KC|started|startup|traceback' | tail -8 || echo "  (no error lines — clean boot)"
echo DONE
