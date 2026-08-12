#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== is domain-certificate secret Flux/Helm-owned or hand-applied? (ownerRefs / managed-by) ==="
kubectl -n platform-mesh-system get secret domain-certificate -o jsonpath='ownerRefs={.metadata.ownerReferences} labels={.metadata.labels} annotations.helm={.metadata.annotations.meta\.helm\.sh/release-name} lastApplied={.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}{"\n"}' 2>&1 | grep -av memcache | head -c 400; echo
echo "=== WHO serves/uses kcp.api.ai-trust-1 host? (the SAN the LE cert does NOT cover) ==="
echo "--- any gateway listener with kcp.api host? ---"
kubectl -n platform-mesh-system get gateway k8sapi-gateway -o jsonpath='{range .spec.listeners[*]}{.name}={.hostname}{"\n"}{end}' 2>&1 | grep -av memcache | grep -i kcp || echo "  (no gateway listener uses kcp.api — good)"
echo "--- does anything resolve/serve kcp.api externally? (the syncagent used it INTERNALLY via hostAlias, not via this gateway) ---"
echo "  note: kcp.api.<domain> was the VW-endpoint name; syncagents reach it via in-cluster hostAlias to frontproxy, NOT via the public Traefik gateway on :443."
echo "=== confirm the new LE secret has crt+key+ (ca?) so overwriting domain-certificate keeps it valid ==="
kubectl -n platform-mesh-system get secret cert-aitrust-full -o jsonpath='type={.type} keys={.data}{"\n"}' 2>&1 | grep -av memcache | sed -E 's/(tls\.crt":")[^"]+/\1<...>/; s/(tls\.key":")[^"]+/\1<...>/; s/(ca\.crt":")[^"]+/\1<...>/' | head -c 300; echo
