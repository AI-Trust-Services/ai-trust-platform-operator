#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== operator FULL logs since restart (all levels) ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=40 2>&1 | grep -av memcache | tail -40
echo "=== can the operator SA see the CR? (impersonate) ==="
sk get aitrustplatforminstance -A --as=system:serviceaccount:aitrust-msp:aitrust-msp-operator 2>&1 | grep -av memcache | head
