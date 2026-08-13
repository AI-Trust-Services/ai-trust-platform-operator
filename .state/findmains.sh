#!/bin/bash
G=/mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
for d in ai-system-registry monitoring overview alerts compliance decision-trace-analyzer users; do
  f="$G/$d/backend/app/main.py"
  echo "=== $d :: $f ==="
  if [ -f "$f" ]; then
    grep -nE "from ai_trust_logging|add_middleware|CORSMiddleware|allow_headers=|\)$|include_router" "$f" | head -12
  else
    echo "  (no main.py at that path)"
    find "$G/$d" -name main.py 2>/dev/null | head
  fi
done
