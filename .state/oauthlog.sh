#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-25veqwflh7syq7fm-d
POD=$(sk -n "$NS" get pods 2>/dev/null | grep -av memcache | grep oauth2-proxy | grep Running | awk '{print $1}' | head -1)
echo "pod=$POD"
# fire 2 requests: bare, and with a fake callback path
sk -n "$NS" run pf-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet -- sh -c '
curl -sS -o /dev/null -w "GET / : %{http_code}\n" -H "Host: 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu" -H "X-Forwarded-Proto: https" http://oauth2-proxy:8080/ ;
curl -sS -o /dev/null -w "GET /oauth2/start : %{http_code} -> %{redirect_url}\n" -H "Host: 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu" -H "X-Forwarded-Proto: https" http://oauth2-proxy:8080/oauth2/start ;
curl -sS -o /dev/null -w "GET /oauth2/callback : %{http_code}\n" -H "Host: 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu" -H "X-Forwarded-Proto: https" http://oauth2-proxy:8080/oauth2/callback
' 2>&1 | grep -av memcache
sleep 2
echo "=== oauth2-proxy logs for those requests (the 403 REASON) ==="
sk -n "$NS" logs "$POD" --tail=25 2>&1 | grep -av memcache | grep -ivE 'start worker|nginx' | tail -20
