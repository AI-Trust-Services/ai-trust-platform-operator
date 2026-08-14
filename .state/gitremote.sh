#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
echo "=== remote url ==="
git remote -v 2>&1 | grep -avi memcache
echo "=== current branch + HEAD ==="
git branch --show-current 2>&1; git log --oneline -1 2>&1
echo "=== does mircea-mt2 already exist (local/remote)? ==="
git branch -a 2>&1 | grep -i 'mircea-mt2' || echo "  (no mircea-mt2 yet)"
echo "=== is a credential helper / token configured for github.com? (do NOT print secrets) ==="
git config --get credential.helper 2>&1 | grep -avi memcache || echo "  (no credential.helper)"
echo DONE
