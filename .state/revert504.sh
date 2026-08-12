#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
echo "=== revert experimental args (back to working-standalone parity) ==="
sk -n "$NS" get deploy oauth2-proxy -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
args=d['spec']['template']['spec']['containers'][0]['args']
args=[a for a in args if a not in ('--reverse-proxy=true','--skip-provider-button=true')]
print(json.dumps(args))
" > "$STATE/cleanargs.json"
sk -n "$NS" patch deploy oauth2-proxy --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":$(cat "$STATE/cleanargs.json")}]" 2>&1 | grep -av memcache
sk -n "$NS" rollout status deploy/oauth2-proxy --timeout=90s 2>&1 | grep -av memcache | tail -1
H=25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
echo "=== EXTERNAL through gateway: repeat 3x (is it 403 sign-in page, or 504 backend-unreachable?) ==="
for n in 1 2 3; do
sk -n platform-mesh-system run pge-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- \
  curl -sk -o /dev/null -w "ext try$n: http=%{http_code} time=%{time_total}s\n" -H 'Accept: text/html' "https://$H/" 2>&1 | grep -av memcache
done
echo "=== is the app HTTPRoute attached to the gateway (attachedRoutes/accepted)? ==="
sk -n "$GATEWAY_NS" get httproute aitp-25veqwflh7syq7fm-d-app -o jsonpath='{range .status.parents[*]}accepted={.conditions[?(@.type=="Accepted")].status} resolved={.conditions[?(@.type=="ResolvedRefs")].status}{"\n"}{end}' 2>&1 | grep -av memcache
