#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== what serves the gateway LB 130.214.18.166? find the Service + its pods ==="
sk -A get svc 2>&1 | grep -av memcache | grep -E 'LoadBalancer|130.214.18.166' | head
echo "=== gatewayClass + controller ==="
sk get gatewayclass 2>&1 | grep -av memcache | head
sk get gateway k8sapi-gateway -n platform-mesh-system -o jsonpath='class={.spec.gatewayClassName}{"\n"}' 2>&1 | grep -av memcache
echo "=== pods that look like the gateway data plane (any ns) ==="
sk -A get pods 2>&1 | grep -av memcache | grep -iE 'traefik|gateway|envoy|contour|istio|nginx' | grep -ivE 'graphql|kubernetes-graphql' | head
echo "=== does the wildstar listener show any WARNING about the new certRef? full listener status ==="
sk -n platform-mesh-system get gateway k8sapi-gateway -o jsonpath='{range .status.listeners[?(@.name=="terminate-wildstar")]}{.conditions}{"\n"}{end}' 2>&1 | grep -av memcache | head -c 600; echo
