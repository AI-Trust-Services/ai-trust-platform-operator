#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "== keycloak.py full =="
kubectl -n "$NS" exec deploy/users-backend -- sh -lc 'cat /app/app/keycloak.py' 2>&1 | grep -avi memcache
echo "== admin endpoints the app hits =="
kubectl -n "$NS" exec deploy/users-backend -- sh -lc 'grep -rnoE "/(users|roles|groups|clients)[a-zA-Z/_{}-]*|role-mappings" /app/app 2>/dev/null | grep -viE "[.]pyc" | sort -u | head -40' 2>&1 | grep -avi memcache | head -40
echo DONE
