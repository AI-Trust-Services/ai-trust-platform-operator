#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step2-trust.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system
BK=.state/backup-dnscert2
BUNDLE="$BK/combined-ca.pem"
[ -s "$BUNDLE" ] || { echo "MISSING combined-ca.pem"; exit 4; }
setup_kcp >/dev/null 2>&1; kcp_portforward >/dev/null 2>&1
for i in $(seq 1 15); do kc root get workspace >/dev/null 2>&1 && break; sleep 2; done

# helper: set spec.jwt[0].issuer.certificateAuthority = combined bundle on WAC <ws> <name>
patch_wac(){
  local ws="$1" name="$2"
  # read current object json, inject CA via jq (jq is in the WSL env; if not, fallback to python)
  kc "$ws" get workspaceauthenticationconfiguration "$name" -o json 2>/dev/null | grep -avi memcache > /tmp/wac.json
  [ -s /tmp/wac.json ] || { echo "  [$ws/$name] FETCH FAILED"; return 1; }
  CA="$(cat "$BUNDLE")" jq '.spec.jwt[0].issuer.certificateAuthority = env.CA
        | del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.generation,.status)' \
      /tmp/wac.json > /tmp/wac.patched.json 2>/tmp/jqerr || { echo "  [$ws/$name] jq err: $(cat /tmp/jqerr)"; return 1; }
  kc "$ws" apply -f /tmp/wac.patched.json 2>&1 | grep -avi memcache | sed "s/^/  [$ws\/$name] /"
}

echo "############ A. patch root WAC ############"
patch_wac root orgs-authentication

echo "############ B. patch all 8 root:orgs WACs ############"
for n in aitrustdemo aitrustfresh aitrustg2 demo mirceatest mirceatest2 mirceatest3 poc; do
  patch_wac root:orgs "$n"
done

echo "############ C. update domain-certificate-ca secret to combined bundle (iam-service + infra keycloak read this) ############"
kubectl -n "$GWNS" create secret generic domain-certificate-ca \
  --from-file=tls.crt="$BUNDLE" --from-file=ca.crt="$BUNDLE" \
  --dry-run=client -o yaml 2>/dev/null | grep -avi memcache | kubectl apply -f - 2>&1 | grep -avi memcache

echo "############ D. roll iam-service so it reloads the CA ############"
kubectl -n "$GWNS" rollout restart deploy/iam-service 2>&1 | grep -avi memcache
kubectl -n "$GWNS" rollout status deploy/iam-service --timeout=120s 2>&1 | grep -avi memcache | tail -1

echo "############ E. verify a WAC now carries the 3-CA bundle ############"
kc root get workspaceauthenticationconfiguration orgs-authentication -o jsonpath='{.spec.jwt[0].issuer.certificateAuthority}' 2>/dev/null | grep -avi memcache | grep -c 'BEGIN CERT' | sed 's/^/  root WAC cert count: /'
echo STEP2_APPLY_DONE
