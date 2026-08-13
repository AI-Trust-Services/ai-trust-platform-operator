#!/bin/bash
# Audit part 2: OpenFGA store contents, RLS enforcement, operator, subscriptions, routing, new-org readiness
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system; LB=130.214.18.166
line(){ echo "======================================================================"; echo "== $1"; echo "======================================================================"; }

line "6. OPENFGA store 'ai-trust-mt' — roles present in MESH OpenFGA?"
STOREID=$(kubectl -n "$NS" get deploy registry -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="OPENFGA_STORE_ID")]}{.value}{end}' 2>/dev/null)
echo "store id: $STOREID"
kubectl -n "$NS" run fga-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "
    B=http://openfga.$GWNS.svc.cluster.local:8080
    echo '-- authorization models (count) --'; curl -s \$B/stores/$STOREID/authorization-models | head -c 120; echo
    echo '-- sample check: platform_administrator can_manage_iam --'
    curl -s -X POST \$B/stores/$STOREID/check -H 'content-type: application/json' -d '{\"tuple_key\":{\"user\":\"role:platform_administrator#member\",\"relation\":\"can_manage_iam\",\"object\":\"platform:global\"}}'
    echo; echo '-- sample check: auditor can_manage_iam (expect false) --'
    curl -s -X POST \$B/stores/$STOREID/check -H 'content-type: application/json' -d '{\"tuple_key\":{\"user\":\"role:auditor#member\",\"relation\":\"can_manage_iam\",\"object\":\"platform:global\"}}'
    echo
  " 2>&1 | grep -avi memcache

line "7. RLS ENFORCEMENT — is the app role really non-superuser + is RLS enabled on tables?"
PGPOD=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^postgres' | awk '{print $1}' | head -1)
echo "pg pod: $PGPOD"
kubectl -n "$NS" exec "$PGPOD" -- sh -lc 'PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB -tA -c "
SELECT '\''rolsuper: '\''||rolname||'\''='\''||rolsuper FROM pg_roles WHERE rolname IN ('\''postgres'\'','\''ai_trust_app'\'');
SELECT '\''rls_tables: '\''||count(*) FROM pg_tables WHERE schemaname='\''public'\'' AND rowsecurity=true;
"' 2>&1 | grep -avi memcache | grep -iE 'rolsuper|rls_tables'

line "8. SUBSCRIPTION operator (image tag v4?) + running?"
kubectl -n "$NS" get deploy -o wide 2>/dev/null | grep -avi memcache | grep -iE 'operator' | awk '{print $1, $7}'
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -i operator | awk '{printf "%-52s %-8s %s\n",$1,$2,$3}'

line "9. Existing SUBSCRIPTIONS (pocmt status) via CRD on the shoot"
kubectl get crd 2>/dev/null | grep -avi memcache | grep -i subscription
echo DONE_AUDIT2
