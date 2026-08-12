#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== standalone oauth2-proxy ENV vars (skip-auth via env? extra config?) ==="
sk -n ai-trust-app get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -av memcache | grep -ivE 'SECRET|PASSWORD'
echo "=== instance d oauth2-proxy ENV vars (compare) ==="
sk -n aitp-25veqwflh7syq7fm-d get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -av memcache | grep -ivE 'SECRET|PASSWORD'
echo "=== does standalone / redirect to login when fetched fresh, or serve app? full header ==="
STD=ai-trust-platform-main.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
sk -n platform-mesh-system run ph-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -D - -o /dev/null -H 'Accept: text/html' "https://$STD/" 2>&1 | grep -av memcache | grep -iE 'HTTP/|location|set-cookie' | head