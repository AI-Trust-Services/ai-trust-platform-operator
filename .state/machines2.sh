#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== cloudprofile name on the shoot ==="
CP=$(garden get shoot "$SHOOT_NAME" -n "$PROJECT" -o jsonpath='{.spec.cloudProfileName}' 2>/dev/null)
echo "cloudProfile=$CP"
echo "=== ALL machine types (name / cpu / memory) ==="
garden get cloudprofile "$CP" -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
for m in d.get("spec",{}).get("machineTypes",[]):
    print(m.get("name"), m.get("cpu"), m.get("memory"))
' 2>&1 | grep -av memcache | sort | head -60
