#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
echo "=== branch + HEAD ==="
git branch --show-current 2>&1
git log --oneline -1 2>&1
echo
echo "=== git status (uncommitted changes) ==="
git status --short 2>&1
echo
echo "=== untracked new files (the libs/tenancy package, 0009, updategit.md, _tenant.py) ==="
git status --short 2>&1 | grep '^??' | head -30
echo
echo "=== summary counts ==="
echo "modified: $(git status --short 2>&1 | grep -c '^ M')"
echo "untracked: $(git status --short 2>&1 | grep -c '^??')"
