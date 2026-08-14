#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== curl the shell Service directly (in-cluster) to see response headers ==="
kubectl -n "$NS" run hh-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c 'curl -s -D - -o /dev/null http://shell:80/ | grep -iE "content-security-policy|x-frame-options|strict-transport|x-content-type|referrer-policy|access-control-allow-origin"' 2>&1 | grep -avi memcache | head
echo "(expect CSP frame-ancestors, X-Frame-Options SAMEORIGIN, HSTS, nosniff, Referrer-Policy; NO Access-Control-Allow-Origin: *)"
echo DONE
