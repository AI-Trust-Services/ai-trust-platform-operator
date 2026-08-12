#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-33hins0iklcwfg45-d
echo "=== $NS deploy readiness ==="
sk -n "$NS" get deploy --no-headers 2>&1 | grep -av memcache | awk '{r=($2=="1/1")?"ok ":"WAIT"; print r,$1,$2}' | sort | head -30
echo "=== jobs ==="
sk -n "$NS" get jobs --no-headers 2>&1 | grep -av memcache | head
echo "=== pod node placement ==="
sk -n "$NS" get pods -o wide --no-headers 2>&1 | grep -av memcache | awk '{print $7}' | sort -u | head
echo "=== the shoot-side CR status (operator writes here; syncagent mirrors up to the portal) ==="
sk -n 33hins0iklcwfg45 get aitrustplatforminstance d -o jsonpath='phase={.status.phase} ready={.status.ready}{"\n"}' 2>&1 | grep -av memcache
