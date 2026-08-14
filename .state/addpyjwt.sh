#!/bin/bash
# Add PyJWT[crypto] explicitly to each backend + worker requirements.txt (repo pins versions
# per-service). libs/tenancy declares it too, but the pinned-requirements convention wants it
# explicit. Idempotent.
set -e
G=/mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
PYJWT='PyJWT[crypto]==2.9.0'
FILES="
ai-system-registry/backend/requirements.txt
monitoring/backend/requirements.txt
overview/backend/requirements.txt
alerts/backend/requirements.txt
compliance/backend/requirements.txt
decision-trace-analyzer/backend/requirements.txt
users/backend/requirements.txt
policy-checker-worker/requirements.txt
"
for f in $FILES; do
  p="$G/$f"
  if grep -qi 'PyJWT' "$p"; then
    echo "$f: already has PyJWT"
  else
    # insert before the first '-e /app/libs' line so it installs before the local libs
    awk -v dep="$PYJWT" '!done && /^-e \/app\/libs/ { print dep; done=1 } { print }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
    echo "$f: += $PYJWT"
  fi
done
echo "=== verify ==="
for f in $FILES; do echo "--- $f ---"; grep -nE 'PyJWT|libs/tenancy' "$G/$f" | head; done
echo DONE
