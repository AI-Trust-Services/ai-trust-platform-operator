#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-33hins0iklcwfg45-d
echo "=== keycloak env (KC_HOSTNAME / RELATIVE_PATH / STRICT) ==="
sk -n "$NS" get deploy keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'KC_HOSTNAME|RELATIVE|STRICT|PROXY'
echo "=== keycloak readiness path ==="
sk -n "$NS" get deploy keycloak -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}{"\n"}' 2>&1 | grep -av memcache
echo "=== oauth2-proxy args ==="
sk -n "$NS" get deploy oauth2-proxy -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -av memcache
echo "=== keycloak-provision job status + did it create realm ai-trust + client oauth2-proxy? ==="
sk -n "$NS" get job keycloak-provision -o jsonpath='succeeded={.status.succeeded} failed={.status.failed}{"\n"}' 2>&1 | grep -av memcache
echo "--- provision job log tail ---"
sk -n "$NS" logs job/keycloak-provision --tail=25 2>&1 | grep -av memcache | tail -25
