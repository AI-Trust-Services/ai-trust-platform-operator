#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== syncagent crash logs ==="
sk -n aitrust-msp logs deploy/aitrust-syncagent --tail=30 2>&1 | grep -av memcache | tail -30
echo "=== previous container logs (if crashed) ==="
POD=$(sk -n aitrust-msp get pods -l app.kubernetes.io/name=aitrust-syncagent -o name 2>/dev/null | head -1)
sk -n aitrust-msp logs "$POD" --previous --tail=25 2>&1 | grep -av memcache | tail -25
