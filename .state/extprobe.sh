#!/bin/bash
# READ-ONLY external probes: public DNS + served TLS cert. No cluster access needed.
set +e
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"
WORKING="25veqwflh7syq7fm-d.$SUF"
APEX="portal.$SUF"     # portal apex-ish guess
RANDOM_HOST="doesnotexist-$RANDOM.$SUF"

echo "===== label count of working host ====="
echo "$WORKING" | awk -F. '{print NF" labels: "$0}'

for H in "$SUF" "$WORKING" "$RANDOM_HOST" "*.$SUF"; do
  echo
  echo "===== DNS A/CNAME: $H ====="
  # getent + dig if present
  getent hosts "$H" 2>&1 | head -3
  if command -v dig >/dev/null 2>&1; then
    dig +short "$H" A 2>&1 | head -5
    echo "-- CNAME --"; dig +short "$H" CNAME 2>&1 | head -3
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$H" 2>&1 | grep -aiE 'address|name|canonical' | head -6
  fi
done

echo
echo "===== wildcard resolution test (random host should resolve iff wildcard A-record exists) ====="
if command -v dig >/dev/null 2>&1; then
  echo "random -> $(dig +short "$RANDOM_HOST" A | head -1)"
  echo "working -> $(dig +short "$WORKING" A | head -1)"
fi

echo
echo "===== served TLS cert on working host (443, 15s cap) ====="
if command -v openssl >/dev/null 2>&1; then
  echo | /usr/bin/timeout 15 openssl s_client -connect "$WORKING:443" -servername "$WORKING" 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates -ext subjectAltName 2>/dev/null | head -20
  echo "openssl-rc=$?"
else
  echo "no openssl"
fi

echo
echo "===== curl verify (does a real CA trust it?) ====="
/usr/bin/timeout 15 curl -sS -o /dev/null -w "http_code=%{http_code} ssl_verify=%{ssl_verify_result}\n" "https://$WORKING/" 2>&1 | head -3
