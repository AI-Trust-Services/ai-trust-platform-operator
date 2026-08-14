#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system

echo "=== A. syncagent PublishedResource full spec — projection options available? ==="
kubectl get publishedresources.syncagent.kcp.io publish-aitrust-mt-subscriptions -o yaml 2>&1 | grep -avi memcache | grep -viE '^ *(resourceVersion|uid|generation|creationTimestamp|managedFields|time:|fieldsV1|f:|manager:|operation:|apiVersion: syncagent)' | head -60

echo "=== B. can we map cluster-id -> org? Check kcp CRDs on the shoot ==="
kubectl get crd 2>&1 | grep -avi memcache | grep -iE 'kcp|tenancy|core.platform-mesh|account|logicalcluster' | head

echo "=== C. is there an APIExportEndpointSlice / kcp workspace info reachable? ==="
kubectl get apiexportendpointslices.apis.kcp.io -A 2>&1 | grep -avi memcache | head -5 || echo "  (no apiexportendpointslices on shoot)"

echo "=== D. mesh realms vs the consumer cluster-ids on the subs (is realm==cluster-id or ==org name?) ==="
echo "-- current subs: cluster-id (ns) vs spec.org --"
kubectl get subscriptions.sub.aitrustmt.msp -A -o jsonpath='{range .items[*]}{.metadata.namespace}  org={.spec.org}{"\n"}{end}' 2>&1 | grep -avi memcache | head
echo "-- realms in mesh KC (name == org, NOT cluster-id) --"
KCPOD=$(kubectl -n "$GWNS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep -E '^keycloak-[0-9]' | awk '{print $1}' | head -1)
kubectl -n "$GWNS" exec "$KCPOD" -- sh -lc 'KA=${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}; KP=${KC_BOOTSTRAP_ADMIN_PASSWORD:-admin}; /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/keycloak --realm master --user "$KA" --password "$KP" >/dev/null 2>&1; /opt/keycloak/bin/kcadm.sh get realms --fields realm 2>/dev/null' 2>&1 | grep -avi memcache | grep '"realm"' | head -20
echo DONE
