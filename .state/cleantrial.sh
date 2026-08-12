#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
GW=k8sapi-gateway; NS=platform-mesh-system
echo "=== clean up the trial listener terminate-testai (operator reverts the route sectionName anyway) ==="
IDX=$(sk -n "$NS" get gateway "$GW" -o json 2>/dev/null | python3 -c "import json,sys;l=json.load(sys.stdin)['spec']['listeners'];print(next((i for i,x in enumerate(l) if x['name']=='terminate-testai'),-1))")
echo "terminate-testai index=$IDX"
[ "$IDX" -ge 0 ] 2>/dev/null && sk -n "$NS" patch gateway "$GW" --type=json -p "[{\"op\":\"remove\",\"path\":\"/spec/listeners/$IDX\"}]" 2>&1 | grep -av memcache
echo "=== Programmed after cleanup ==="
sk -n "$NS" get gateway "$GW" -o jsonpath='Programmed={.status.conditions[?(@.type=="Programmed")].status}{"\n"}' 2>&1 | grep -av memcache
