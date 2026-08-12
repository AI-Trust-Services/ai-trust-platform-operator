#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"; LB=130.214.18.166
echo "=== confirm baseline: an instance host serves self-signed (as before), Programmed True ==="
kubectl -n platform-mesh-system get gateway k8sapi-gateway -o jsonpath='{range .spec.listeners[*]}{.name}={.tls.certificateRefs[0].name}{" "}{end}{"\n"}Programmed={.status.conditions[?(@.type=="Programmed")].status}{"\n"}' 2>&1 | grep -av memcache
echo "=== how is Traefik's DEFAULT cert set? (this is what actually served) — full TLS-related args + any default-cert file/secret ==="
kubectl -n default get deploy traefik -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'tls|cert|default|entrypoint'
echo "=== does traefik mount a default cert secret (volumes)? ==="
kubectl -n default get deploy traefik -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}={.secret.secretName}{" "}{end}{"\n"}' 2>&1 | grep -av memcache
echo "=== any Traefik dynamic config / TLSStore 'default' anywhere? ==="
kubectl get tlsstore -A 2>&1 | grep -av memcache | head
kubectl -n default get cm 2>&1 | grep -av memcache | grep -iE 'traefik|tls' | head
