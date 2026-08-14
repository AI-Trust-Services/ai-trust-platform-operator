#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== which frontend bundles still throw 'Missing required environment variable' ? ====="
for d in ai-system-registry-frontend monitoring-frontend overview-frontend alerts-frontend compliance-frontend decision-trace-analyzer-frontend users-frontend; do
  R=$(kubectl -n "$NS" exec deploy/"$d" -- sh -c 'grep -rIl "Missing required environment variable" /usr/share/nginx/html/assets/ 2>/dev/null | head -1' 2>/dev/null | grep -avi memcache)
  U=$(kubectl -n "$NS" exec deploy/"$d" -- sh -c 'grep -rhoE "VITE_USERS_API_BASE|api/users/v1" /usr/share/nginx/html/assets/*.js 2>/dev/null | sort -u | tr "\n" " "' 2>/dev/null | grep -avi memcache)
  printf '  %-38s missing-env-throw=%s   users-token:[%s]\n' "$d" "$([ -n "$R" ] && echo YES || echo no)" "$U"
done
echo
echo "  (YES + VITE_USERS_API_BASE literal = built WITHOUT the arg -> must rebuild with it)"
echo DONE
