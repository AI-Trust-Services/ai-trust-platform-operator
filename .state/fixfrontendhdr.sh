#!/bin/bash
# SEC-H: replace permissive framing/CORS headers in all 7 frontend nginx.conf with same-origin-safe
# values. MFEs are served same-origin through the shell proxy, so they need no wildcard CORS and must
# not advertise ALLOWALL/frame-ancestors * (those pass through the shell and win). Idempotent.
set -e
G=/mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
FRONTENDS="ai-system-registry monitoring overview alerts compliance decision-trace-analyzer users"
for f in $FRONTENDS; do
  p="$G/$f/frontend/nginx.conf"
  [ -f "$p" ] || { echo "$f: no nginx.conf"; continue; }
  # X-Frame-Options ALLOWALL -> SAMEORIGIN
  sed -i 's/add_header X-Frame-Options "ALLOWALL";/add_header X-Frame-Options "SAMEORIGIN";/g' "$p"
  # CSP frame-ancestors * -> 'self'
  sed -i "s/add_header Content-Security-Policy \"frame-ancestors \*\";/add_header Content-Security-Policy \"frame-ancestors 'self'\";/g" "$p"
  # remove wildcard CORS lines entirely (same-origin via shell — not needed)
  sed -i '/add_header Access-Control-Allow-Origin "\*";/d' "$p"
  sed -i '/add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";/d' "$p"
  sed -i '/add_header Access-Control-Allow-Headers "\*";/d' "$p"
  echo "$f: hardened"
done
echo "=== verify no permissive headers remain ==="
grep -rn 'ALLOWALL\|frame-ancestors \*\|Access-Control-Allow-Origin "\*"' $G/*/frontend/nginx.conf 2>&1 | head || echo "(none — clean)"
echo "=== sample (alerts) ==="
sed -n '1,25p' "$G/alerts/frontend/nginx.conf"
echo DONE
