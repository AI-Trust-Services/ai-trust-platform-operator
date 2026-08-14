#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
TOKENFILE="/mnt/c/Claude/Credentials/git_token.txt"
[ -f "$TOKENFILE" ] || TOKENFILE="/c/Claude/Credentials/git_token.txt"
[ -f "$TOKENFILE" ] || { echo "TOKEN FILE MISSING (tried /mnt/c and /c)"; exit 1; }
TOKEN="$(tr -d ' \r\n' < "$TOKENFILE")"
[ -n "$TOKEN" ] || { echo "TOKEN EMPTY"; exit 1; }
echo "token loaded (len=${#TOKEN}); pushing mircea-mt2 to github.com (secret not printed)…"
# push via an inline authenticated URL so no token is written to git config; capture status only
git push "https://x-access-token:${TOKEN}@github.com/AI-Trust-Services/ai-trust-platform.git" mircea-mt2:mircea-mt2 2>&1 \
  | sed -E "s#x-access-token:[^@]*@#x-access-token:***@#g" \
  | grep -aviE 'memcache' \
  | grep -iE 'mircea-mt2|remote:|error|denied|fatal|rejected|-> |up-to-date|Everything|new branch|Total|Writing|Enumerating' \
  | head -25
echo "EXIT_STATUS=${PIPESTATUS[0]}"
echo DONE
