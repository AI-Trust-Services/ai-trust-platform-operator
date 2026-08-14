#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
echo "=== branch + HEAD ==="
git branch --show-current
git log --oneline -1
echo "=== status (what will be committed) ==="
git status --short
echo "=== diffstat (tracked changes) ==="
git diff --stat | tail -5
echo "=== untracked ==="
git status --short | grep '^??' | wc -l
echo DONE
