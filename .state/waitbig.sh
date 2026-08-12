#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== wait for a real msp-at-big node ==="
for i in $(seq 1 60); do
  N=$(sk get nodes -l worker.gardener.cloud/pool=msp-at-big --no-headers 2>/dev/null | grep -av memcache | grep -c ' Ready ')
  [ "${N:-0}" -ge 1 ] && { echo "big node Ready"; break; }
  sleep 20; printf '.'
done
sk get nodes -l worker.gardener.cloud/pool=msp-at-big 2>&1 | grep -av memcache
echo "=== now cordon the small pool so instance pods prefer the big node ==="
for n in $(sk get nodes -l worker.gardener.cloud/pool=msp-aitrust -o name 2>/dev/null); do
  sk cordon "$n" 2>&1 | grep -av memcache
done
echo "=== bounce the instance pods so they reschedule onto the big node ==="
NS=$(sk get aitrustplatforminstance -A -o jsonpath='{.items[0].status.namespace}' 2>/dev/null)
[ -z "$NS" ] && NS=aitp-q3c0weh7suf5hgjk-my-aitrust
echo "instance ns=$NS"
sk -n "$NS" delete pods --all --wait=false 2>&1 | grep -av memcache | tail -2
