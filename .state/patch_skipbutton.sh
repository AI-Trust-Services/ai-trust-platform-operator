#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }
for ORG in fridaytest livedemo mirceatest mttest2 sohan; do
  D="oauth2-proxy-$ORG"
  # add --skip-provider-button=true if not present
  HAS=$(kubectl -n "$NS" get deploy "$D" -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null | grep -c 'skip-provider-button' || true)
  if [ "$HAS" -eq 0 ]; then
    kubectl -n "$NS" patch deploy "$D" --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--skip-provider-button=true"}]' 2>&1 | f
    echo "  $ORG: patched"
  else
    echo "  $ORG: already has it"
  fi
done
echo "-- wait for rollouts --"
for ORG in fridaytest livedemo mirceatest mttest2 sohan; do
  kubectl -n "$NS" rollout status deploy/oauth2-proxy-$ORG --timeout=90s 2>&1 | f | tail -1
done
echo DONE
