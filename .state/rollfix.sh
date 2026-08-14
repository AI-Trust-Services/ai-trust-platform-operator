#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
echo "=== roll backends + worker to the fixed image ==="
for d in ai-system-registry-backend monitoring-backend overview-backend alerts-backend compliance-backend decision-trace-analyzer-backend users-backend policy-checker-worker; do
  kubectl -n "$NS" rollout restart deploy/$d >/dev/null 2>&1
done
for d in overview-backend ai-system-registry-backend alerts-backend compliance-backend users-backend; do
  kubectl -n "$NS" rollout status deploy/$d --timeout=150s 2>&1 | grep -avi memcache | tail -1
done
echo "=== overview-backend: is the set_config error gone? (health should be 200) ==="
sleep 5
kubectl -n "$NS" logs deploy/overview-backend --tail=12 2>&1 | grep -avi memcache | grep -iE 'set_config|syntax|health|503|200|request.completed|request.error' | tail -8
echo "=== live: /health via the app (through oauth2 it's 200 if db ok) — check backend /health directly ==="
kubectl -n "$NS" exec deploy/overview-backend -- sh -lc 'python -c "
import urllib.request
try:
  r=urllib.request.urlopen(\"http://localhost:8004/health\", timeout=5); print(\"health:\", r.status, r.read().decode()[:80])
except Exception as e: print(\"health err:\", repr(e)[:120])
"' 2>&1 | grep -avi memcache | head
echo DONE
