#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/inv6-accountop.out 2>&1
K(){ kubectl "$@" 2>&1 | grep -avi memcache; }

echo "############ account-operator deploy: args + env + volumes (CA source) ############"
K -n "$MESH_NS" get deploy account-operator -o yaml | grep -avi 'managedFields' | grep -aiE 'image:|--|name:|value:|valueFrom|secretName|configMap|mountPath|key:|OIDC|ISSUER|CA|KEYCLOAK|IDP|issuer|certificate' | head -80

echo; echo "############ account-operator HelmRelease values (Flux) ############"
K get helmrelease -A 2>&1 | grep -aiE 'account|iam|infra' | grep -avi memcache
echo "--- account-operator HR spec.values (grep ca/issuer/keycloak/oidc) ---"
K -n "$MESH_NS" get helmrelease account-operator -o yaml 2>&1 | grep -avi managedFields | grep -aiE 'ca|issuer|keycloak|oidc|cert|domain|host' | head -60

echo; echo "############ iam-service deploy: CA/issuer source ############"
K -n "$MESH_NS" get deploy iam-service -o yaml | grep -avi 'managedFields' | grep -aiE 'image:|--|value:|secretName|configMap|OIDC|ISSUER|CA|KEYCLOAK|issuer|domain|host' | head -60

echo; echo "############ Does account-operator mount a CA that equals the mesh CA? list tls secrets ###########"
K -n "$MESH_NS" get secret account-operator-ca-secret -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > /tmp/ao-ca.pem 2>/dev/null
openssl x509 -in /tmp/ao-ca.pem -noout -subject -issuer -fingerprint 2>&1 | head

echo; echo "############ infra HelmRelease: grep for the WAC/authentication/keycloak CA templating ############"
K -n "$MESH_NS" get helmrelease infra -o yaml 2>&1 | grep -avi managedFields | grep -aiE 'authentication|workspaceauth|keycloak|oidc|certificateAuthority|localCA|local-ca|domain-certificate|caBundle' | head -40
