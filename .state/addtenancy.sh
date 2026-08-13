#!/bin/bash
# Idempotently add libs/tenancy to each backend's Dockerfile (COPY) and requirements.txt (-e).
# tenancy must be installed/copied BEFORE persistence (database.py imports ai_trust_tenancy).
set -e
G=/mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
BACKENDS="ai-system-registry monitoring overview alerts compliance decision-trace-analyzer users"

for d in $BACKENDS; do
  DF="$G/$d/backend/Dockerfile"
  REQ="$G/$d/backend/requirements.txt"

  # --- Dockerfile: add COPY libs/tenancy before the first COPY libs/ line ---
  if ! grep -q "libs/tenancy" "$DF"; then
    # insert before the first "COPY libs/" line
    awk '
      !done && /^COPY libs\// {
        print "COPY libs/tenancy /app/libs/tenancy";
        done=1
      }
      { print }
    ' "$DF" > "$DF.tmp" && mv "$DF.tmp" "$DF"
    echo "$d: Dockerfile += COPY libs/tenancy"
  else
    echo "$d: Dockerfile already has libs/tenancy"
  fi

  # --- requirements.txt: add -e /app/libs/tenancy before persistence (or before logging) ---
  if ! grep -q "libs/tenancy" "$REQ"; then
    if grep -q "libs/persistence" "$REQ"; then
      sed -i '0,\#-e /app/libs/persistence#s##-e /app/libs/tenancy\n-e /app/libs/persistence#' "$REQ"
    else
      sed -i '0,\#-e /app/libs/logging#s##-e /app/libs/tenancy\n-e /app/libs/logging#' "$REQ"
    fi
    echo "$d: requirements.txt += -e /app/libs/tenancy"
  else
    echo "$d: requirements.txt already has libs/tenancy"
  fi
done

echo "=== VERIFY ==="
for d in $BACKENDS; do
  echo "--- $d Dockerfile ---"; grep -nE "COPY libs/(tenancy|persistence|logging)" "$G/$d/backend/Dockerfile"
  echo "--- $d requirements ---"; grep -nE "libs/(tenancy|persistence|logging)" "$G/$d/backend/requirements.txt"
done
echo DONE
