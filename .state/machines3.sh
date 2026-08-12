#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== shoot cloudprofile ref ==="
garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o jsonpath='name={.spec.cloudProfile.name} legacy={.spec.cloudProfileName}{"\n"}' 2>&1 | grep -av memcache
echo "=== all cloudprofiles ==="
garden get cloudprofile 2>&1 | grep -av memcache | head
echo "=== machine types (try each cloudprofile) ==="
for CP in $(garden get cloudprofile -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  echo "--- $CP ---"
  garden get cloudprofile "$CP" -o jsonpath='{range .spec.machineTypes[*]}{.name}{" cpu="}{.cpu}{" mem="}{.memory}{"\n"}{end}' 2>&1 | grep -av memcache | grep -iE 'm_|c16|c32|_m32|_m64|_m128' | head -20
done
