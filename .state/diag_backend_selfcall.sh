#!/bin/bash
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh 2>/dev/null; load_config 2>/dev/null
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp
f(){ grep -avi memcache; }

echo "===== which port does users-backend listen on ====="
kubectl -n "$NS" get deploy users-backend -o jsonpath='{range .spec.template.spec.containers[0].ports[*]}containerPort={.containerPort}{"\n"}{end}' 2>&1 | f

echo; echo "===== self-call /v1/me/permissions from inside users-backend (python urllib), with the proxy header ====="
PYEXPR='import urllib.request,sys
for port in (8000,8001,8080,80,8002):
    for path in ("/v1/me/permissions","/me/permissions","/api/users/v1/me/permissions"):
        url="http://localhost:%d%s"%(port,path)
        req=urllib.request.Request(url,headers={"X-Forwarded-Preferred-Username":"mircea.craciun@sap.com"})
        try:
            r=urllib.request.urlopen(req,timeout=3)
            print("OK",port,path,r.status); print(r.read().decode()[:800]); sys.exit(0)
        except urllib.error.HTTPError as e:
            print("HTTP",port,path,e.code,e.read().decode()[:300])
        except Exception as e:
            pass
print("no endpoint answered")'
kubectl -n "$NS" exec deploy/users-backend -- python -c "$PYEXPR" 2>&1 | f

echo; echo "===== shell(nginx) route: does the fridaytest host reach THIS users-backend? check shell nginx upstream for /api/users ====="
kubectl -n "$NS" exec deploy/shell -- sh -c 'grep -rInE "api/users|users-backend|proxy_pass" /etc/nginx/ 2>/dev/null | head -20' 2>&1 | f
echo DONE
