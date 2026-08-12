#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== is m_c16_m128_v2 (or similar large) in the cloudprofile? ==="
garden get cloudprofile -o json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    items=d.get("items",[d])
    for cp in items:
        for m in cp.get("spec",{}).get("machineTypes",[]):
            n=m.get("name","")
            if "16" in n or "128" in n or n.startswith("m_"):
                print(n, m.get("cpu"), m.get("memory"))
except Exception as e:
    print("err",e)
' 2>&1 | grep -av memcache | head -30
