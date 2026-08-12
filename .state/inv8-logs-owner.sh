#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/inv8-logs-owner.out 2>&1
K(){ kubectl "$@" 2>&1 | grep -avi memcache; }

echo "############ root-kcp logs: oidc / issuer / discovery / x509 ############"
K -n "$MESH_NS" logs root-kcp-565c99f9dc-gdg78 --tail=4000 2>&1 | grep -aiE 'oidc|issuer|discovery|x509|authentication-config|jwks|keycloak|realms' | tail -40

echo; echo "############ domain-certificate-ca secret ownership (Flux/Helm?) ############"
K -n "$MESH_NS" get secret domain-certificate-ca -o jsonpath='labels={.metadata.labels}{"\n"}annotations={.metadata.annotations}{"\n"}ownerRefs={.metadata.ownerReferences}{"\n"}' 2>&1 | grep -avi memcache

echo; echo "############ domain-certificate (served leaf) ownership ############"
K -n "$MESH_NS" get secret domain-certificate -o jsonpath='labels={.metadata.labels}{"\n"}annotations={.metadata.annotations}{"\n"}ownerRefs={.metadata.ownerReferences}{"\n"}' 2>&1 | grep -avi memcache

echo; echo "############ Is domain-certificate-ca produced by a cert-manager Certificate? ############"
K -n "$MESH_NS" get certificate 2>&1 | grep -aiE 'domain|mesh|aitrust|ca' | grep -avi memcache
K -n "$MESH_NS" get issuer 2>&1 | grep -avi memcache
