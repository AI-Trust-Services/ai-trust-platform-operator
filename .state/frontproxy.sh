#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
echo "=== frontproxy health (the TokenReview target) ==="
kubectl -n platform-mesh-system get pods 2>&1 | grep -av memcache | grep -iE 'front-proxy|frontproxy|root-proxy|kcp'
echo "=== frontproxy recent logs — errors / TLS / overload? ==="
kubectl -n platform-mesh-system logs deploy/frontproxy-front-proxy --since=10m 2>&1 | grep -av memcache | grep -iE 'error|tls|x509|refused|timeout|unavail|panic' | tail -12
echo "=== is the graphql-gateway -> frontproxy TokenReview failing repeatedly or transient? count over 10m ==="
kubectl -n platform-mesh-system logs deploy/kubernetes-graphql-gateway --since=10m 2>&1 | grep -av memcache | grep -c 'TokenReview API call failed'
echo "=== gateway pod restarts / age (did my traefik work ripple to it?) ==="
kubectl -n platform-mesh-system get pods 2>&1 | grep -av memcache | grep -E 'graphql-gateway'
echo "=== can the gateway reach frontproxy now? (exec a probe from the gateway pod is distroless; test svc endpoints instead) ==="
kubectl -n platform-mesh-system get endpoints frontproxy-front-proxy 2>&1 | grep -av memcache
echo "=== frontproxy svc + is it Ready/backed? ==="
kubectl -n platform-mesh-system get svc frontproxy-front-proxy 2>&1 | grep -av memcache
