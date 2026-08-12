#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
echo "=== ALL nodes with pool + workload label + instance-type ==="
sk get nodes -o custom-columns='NAME:.metadata.name,POOL:.metadata.labels.worker\.gardener\.cloud/pool,WORKLOAD:.metadata.labels.workload,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,STATUS:.status.conditions[-1].type' 2>&1 | grep -av memcache | grep -E 'NAME|msp'
echo "=== big pool nodes specifically ==="
sk get nodes -l worker.gardener.cloud/pool=msp-at-big 2>&1 | grep -av memcache
