#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

for O in fridaytest mirceatest; do
  echo "======================== oauth2-proxy-$O args ========================"
  kubectl -n "$NS" get deploy oauth2-proxy-$O -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f | sort
  echo
done

echo "======================== DIFF (fridaytest vs mirceatest) ========================"
kubectl -n "$NS" get deploy oauth2-proxy-fridaytest -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f | sort > /tmp/a.txt
kubectl -n "$NS" get deploy oauth2-proxy-mirceatest -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | f | sort > /tmp/b.txt
diff /tmp/a.txt /tmp/b.txt && echo "  (identical args)" || true

echo; echo "======================== proxy pod readiness ========================"
kubectl -n "$NS" get pods -l org=fridaytest -o wide --no-headers 2>&1 | f
kubectl -n "$NS" get pods -l org=mirceatest -o wide --no-headers 2>&1 | f

echo; echo "======================== oauth2-proxy-fridaytest recent logs ========================"
kubectl -n "$NS" logs deploy/oauth2-proxy-fridaytest --tail=40 2>&1 | f | grep -iE 'error|preferred|claim|forward|header|denied|401|403|upstream' | tail -25
echo DONE
