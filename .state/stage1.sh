#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
GW=k8sapi-gateway; NS=platform-mesh-system
echo "=== STAGE 1a: add dedicated listener terminate-testai -> cert-p1 (does NOT touch terminate-wildstar) ==="
sk -n "$NS" patch gateway "$GW" --type=json -p '[{"op":"add","path":"/spec/listeners/-","value":{
  "name":"terminate-testai",
  "hostname":"testai.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu",
  "port":8443,"protocol":"HTTPS",
  "tls":{"mode":"Terminate","certificateRefs":[{"group":"","kind":"Secret","name":"cert-p1","namespace":"platform-mesh-system"}]},
  "allowedRoutes":{"namespaces":{"from":"All"}}
}}]' 2>&1 | grep -av memcache
echo "=== watch Gateway Programmed status (must stay True) — the #1 safety check ==="
for i in 1 2 3 4 5; do
  sk -n "$NS" get gateway "$GW" -o jsonpath='Programmed={.status.conditions[?(@.type=="Programmed")].status} listeners={range .status.listeners[*]}{.name}:{.conditions[?(@.type=="Programmed")].status}{" "}{end}{"\n"}' 2>&1 | grep -av memcache
  sleep 4
done
echo "=== STAGE 1b: repoint ONLY testai's 2 routes to terminate-testai ==="
for r in aitp-33hins0iklcwfg45-testai-app aitp-33hins0iklcwfg45-testai-keycloak; do
  sk -n "$NS" patch httproute "$r" --type=json -p '[{"op":"replace","path":"/spec/parentRefs/0/sectionName","value":"terminate-testai"}]' 2>&1 | grep -av memcache
done
sleep 5
echo "=== route attach status on the new listener ==="
for r in aitp-33hins0iklcwfg45-testai-app aitp-33hins0iklcwfg45-testai-keycloak; do
  echo "$r accepted=$(sk -n "$NS" get httproute "$r" -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null)"
done
