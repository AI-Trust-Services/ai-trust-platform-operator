#!/bin/bash
G=/mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
for d in ai-system-registry monitoring overview alerts compliance decision-trace-analyzer users; do
  echo "=== $d requirements.txt ==="
  cat "$G/$d/backend/requirements.txt" 2>&1
  echo "--- $d Dockerfile COPY libs lines ---"
  grep -nE "COPY .*libs|COPY libs|pip install" "$G/$d/backend/Dockerfile" 2>&1
  echo
done
