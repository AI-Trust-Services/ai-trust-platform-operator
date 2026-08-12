#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== was the CR mirrored to a per-consumer namespace on the shoot? ==="
sk get aitrustplatforminstance -A 2>&1 | grep -av memcache | head
echo "=== operator logs (last 30) ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=30 2>&1 | grep -av memcache | tail -30
echo "=== syncagent sync logs (mirroring?) ==="
sk -n aitrust-msp logs deploy/aitrust-syncagent --tail=15 2>&1 | grep -av memcache | grep -viE 'leaderelection|metrics' | tail -15
