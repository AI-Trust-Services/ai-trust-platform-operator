#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== current pools ==="
garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o jsonpath='{range .spec.provider.workers[*]}{.name}{" "}{.machine.type}{"\n"}{end}' 2>&1 | grep -av memcache
echo "=== find index of the OLD small pool 'msp-aitrust' and remove it ==="
IDX=$(garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o json 2>/dev/null | python3 -c "import json,sys;w=json.load(sys.stdin)['spec']['provider']['workers'];print(next((i for i,x in enumerate(w) if x['name']=='msp-aitrust'),-1))")
echo "index=$IDX"
if [ "$IDX" -ge 0 ] 2>/dev/null; then
  garden patch shoot "$SHOOT_NAME" -n "$PROJECT" --type=json -p "[{\"op\":\"remove\",\"path\":\"/spec/provider/workers/$IDX\"}]" 2>&1 | grep -av memcache
  echo "removed msp-aitrust pool — shoot reconciling (nodes drain + terminate)"
else
  echo "msp-aitrust pool not found (already gone?)"
fi
echo "=== pools after ==="
garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o jsonpath='{range .spec.provider.workers[*]}{.name}{" "}{.machine.type}{"\n"}{end}' 2>&1 | grep -av memcache
