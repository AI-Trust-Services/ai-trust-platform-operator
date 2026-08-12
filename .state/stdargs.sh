#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== find the standalone app namespace ==="
sk get ns 2>&1 | grep -av memcache | grep -iE 'ai-trust-app|aitrust' | grep -v aitp | head
echo "=== LIVE oauth2-proxy args in the standalone (the working one) ==="
for NS in ai-trust-app aitrust; do
  sk -n "$NS" get deploy oauth2-proxy >/dev/null 2>&1 && {
    echo "ns=$NS"
    sk -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -av memcache
    break
  }
done
