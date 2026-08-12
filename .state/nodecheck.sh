#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-q3c0weh7suf5hgjk-my-aitrust
echo "=== msp-aitrust nodes + allocatable/pressure ==="
sk get nodes -l workload=msp-aitrust 2>&1 | grep -av memcache
sk top nodes -l workload=msp-aitrust 2>&1 | grep -av memcache | head
echo "=== not-ready pod states (evicted/OOM/pending?) ==="
sk -n "$NS" get pods 2>&1 | grep -av memcache | grep -vE 'Running|Completed' | head -20
echo "=== any leftover old namespaces still consuming the node? ==="
sk get ns 2>&1 | grep -av memcache | grep -E 'aitp-|Terminating' | head
echo "=== node count in the pool (can it scale?) ==="
sk get nodes -l workload=msp-aitrust --no-headers 2>&1 | grep -av memcache | wc -l
