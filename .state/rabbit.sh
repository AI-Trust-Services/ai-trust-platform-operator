#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
echo "=== rabbitmq pod + describe ==="
sk -n "$NS" get pods -l app=rabbitmq 2>&1 | grep -av memcache
POD=$(sk -n "$NS" get pods -o name 2>/dev/null | grep rabbitmq | head -1)
echo "pod=$POD"
sk -n "$NS" describe "$POD" 2>&1 | grep -av memcache | grep -iE 'state|reason|message|event|warning|back-off|error|readiness|liveness' | tail -20
echo "=== rabbitmq logs ==="
sk -n "$NS" logs "$POD" --tail=20 2>&1 | grep -av memcache | tail -20
