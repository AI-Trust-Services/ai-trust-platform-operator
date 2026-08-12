#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
echo "=== all pods in $NS (any not Running?) ==="
sk -n "$NS" get pods 2>&1 | grep -av memcache | grep -vE 'Running|Completed' ; echo "(only non-running shown above)"
echo "=== shell + oauth2-proxy + registry-frontend status ==="
sk -n "$NS" get deploy shell oauth2-proxy ai-system-registry-frontend -o wide 2>&1 | grep -av memcache
echo "=== curl the app root FROM INSIDE the cluster (bypass browser) — what does oauth2-proxy return? ==="
sk -n "$NS" run probe-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  sh -c 'echo "-- / (via oauth2-proxy) --"; curl -sS -o /dev/null -w "root: http=%{http_code} redirect=%{redirect_url}\n" http://oauth2-proxy:8080/ ; echo "-- shell directly --"; curl -sS -o /dev/null -w "shell: http=%{http_code}\n" http://shell:80/ ; echo "-- shell / body first bytes --"; curl -sS http://shell:80/ | head -c 300' 2>&1 | grep -av memcache
echo ""
echo "=== shell pod logs (is it erroring? missing luigi config?) ==="
sk -n "$NS" logs deploy/shell --tail=15 2>&1 | grep -av memcache | tail -15
