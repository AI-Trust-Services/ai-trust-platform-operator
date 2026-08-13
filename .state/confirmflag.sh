#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; LB=130.214.18.166
H=ai-trust-mt.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== pod + flag ==="
kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -avi memcache | grep '^oauth2-proxy-'
kubectl -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -avi memcache | grep -iE 'unverified|skip-issuer'
echo "=== /oauth2/start still 302 to poc2? ==="
kubectl -n "$NS" run s-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "curl -sk -o /dev/null -w '/oauth2/start: http=%{http_code}\n' --resolve $H:443:$LB 'https://$H/oauth2/start?rd=%2F'" 2>&1 | grep -avi memcache | grep http=
echo "NOTE: the email-verified error is fixed by the flag. Re-login in browser (fresh code) to confirm callback -> 302 into app."
echo DONE
