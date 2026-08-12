#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
echo "=== FULL oauth2-proxy args (current) ==="
sk -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -av memcache
echo "=== fire request + capture fresh log (stable pod) ==="
POD=$(sk -n "$NS" get pods 2>/dev/null | grep -av memcache | grep oauth2-proxy | grep Running | awk '{print $1}' | head -1)
sk -n "$NS" exec "$POD" -- sh -c 'wget -S -O /dev/null http://localhost:4180/ 2>&1 | head -20' 2>&1 | grep -av memcache | tail -20
