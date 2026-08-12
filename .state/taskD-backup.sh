#!/bin/bash
# TASK D — READ-ONLY live backup of DNS/cert/routing. NO apply/patch/delete/restart.
# Attempts one non-interactive garden mint (hard 30s cap). If it hangs on OIDC => report login expired.
set +e
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP || exit 1
source scripts/lib.sh
load_config
BK="$STATE/backup-dnscert"; mkdir -p "$BK"
GK="$PREREQ/garden-kubeconfig.yaml"
TO=/usr/bin/timeout

echo "===== garden kubeconfig present? ====="
ls -la "$GK" 2>&1 | head -2

echo "===== STEP 0: mint shoot admin kubeconfig (direct kubectl, 30s hard cap) ====="
PAYLOAD='{"apiVersion":"authentication.gardener.cloud/v1alpha1","kind":"AdminKubeconfigRequest","spec":{"expirationSeconds":14400}}'
resp="$($TO 30 kubectl --kubeconfig "$GK" create -f - --raw "/apis/core.gardener.cloud/v1beta1/namespaces/${PROJECT}/shoots/${SHOOT_NAME}/adminkubeconfig" <<<"$PAYLOAD" 2>&1)"
rc=$?
echo "mint-rc=$rc"
if [ "$rc" -eq 124 ]; then
  echo "RESULT=GARDEN_LOGIN_EXPIRED_TIMED_OUT_ON_OIDC"
  echo "SHOOT_UNREACHABLE"
  exit 7
fi
if echo "$resp" | grep -q '"kubeconfig"'; then
  echo "$resp" | jq -r '.status.kubeconfig' | base64 -d > "$SHOOT_KUBECONFIG"
  echo "RESULT=MINT_OK bytes=$(wc -c < "$SHOOT_KUBECONFIG")"
else
  echo "RESULT=NO_KUBECONFIG (sanitized first lines):"
  echo "$resp" | grep -aiv -E 'BEGIN|END|[A-Za-z0-9+/=]{40,}' | head -8
  echo "SHOOT_UNREACHABLE"
  exit 7
fi

echo
echo "===== STEP 1: gateway.yaml ====="
$TO 30 kubectl --kubeconfig "$SHOOT_KUBECONFIG" -n "$GATEWAY_NS" get gateway "$GATEWAY_NAME" -o yaml </dev/null > "$BK/gateway.yaml" 2>"$BK/gateway.err"
echo "gateway-rc=$? bytes=$(wc -c < "$BK/gateway.yaml" 2>/dev/null)"
head -3 "$BK/gateway.err" 2>/dev/null

echo
echo "===== STEP 2: domain-certificate secret.yaml ====="
$TO 30 kubectl --kubeconfig "$SHOOT_KUBECONFIG" -n "$GATEWAY_NS" get secret domain-certificate -o yaml </dev/null > "$BK/secret.yaml" 2>"$BK/secret.err"
echo "secret-rc=$? bytes=$(wc -c < "$BK/secret.yaml" 2>/dev/null)"

echo
echo "===== STEP 3: AITrust HTTPRoutes (all in gateway ns) ====="
$TO 30 kubectl --kubeconfig "$SHOOT_KUBECONFIG" -n "$GATEWAY_NS" get httproute -o yaml </dev/null > "$BK/httproutes.yaml" 2>"$BK/httproutes.err"
echo "httproutes-rc=$? bytes=$(wc -c < "$BK/httproutes.yaml" 2>/dev/null)"

echo
echo "===== STEP 4: DNSEntry CRs (all ns) ====="
$TO 30 kubectl --kubeconfig "$SHOOT_KUBECONFIG" get dnsentry -A -o yaml </dev/null > "$BK/dnsentries.yaml" 2>"$BK/dnsentries.err"
echo "dnsentry-rc=$? bytes=$(wc -c < "$BK/dnsentries.yaml" 2>/dev/null)"
head -3 "$BK/dnsentries.err" 2>/dev/null

echo
echo "===== STEP 5: Certificate CRs (all ns) ====="
$TO 30 kubectl --kubeconfig "$SHOOT_KUBECONFIG" get certificate -A -o yaml </dev/null > "$BK/certificates.yaml" 2>"$BK/certificates.err"
echo "certificate-rc=$? bytes=$(wc -c < "$BK/certificates.yaml" 2>/dev/null)"
head -3 "$BK/certificates.err" 2>/dev/null

echo
echo "===== DONE — backup dir listing ====="
ls -la "$BK"
