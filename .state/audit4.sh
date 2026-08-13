#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system
STOREID=01KZX8TV6TMMF3G3F9DTE87YV4
line(){ echo "== $1 =="; }

line "A. ALL 'user:' subject tuples that are NOT role:* (i.e. actual user->role grants)"
kubectl -n "$NS" run fga-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -s -X POST http://openfga.$GWNS.svc.cluster.local:8080/stores/$STOREID/read -H 'content-type: application/json' -d '{}'" 2>&1 | grep -avi memcache | tr '}' '\n' | grep -iE '"user":"user:' | head -40
echo "----(if nothing above, NO user is assigned any role)----"

line "B. How does permissions.py build the subject? (user: prefix, which header)"
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc '
find / -name permissions.py -path "*ai_trust_authorization*" 2>/dev/null | head -1
' 2>&1 | grep -avi memcache | head -2
kubectl -n "$NS" exec deploy/ai-system-registry-backend -- sh -lc '
F=$(find / -name permissions.py -path "*ai_trust_authorization*" 2>/dev/null | head -1); grep -nE "user:|X-Forwarded|Preferred|subject|role:|INITIAL_ADMIN|_check|check\(" "$F" | head -40
' 2>&1 | grep -avi memcache | head -40

line "C. INITIAL_ADMIN_USER value anywhere in registry env?"
kubectl -n "$NS" get deploy ai-system-registry-backend -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'ADMIN|USER'
echo DONE_AUDIT4
