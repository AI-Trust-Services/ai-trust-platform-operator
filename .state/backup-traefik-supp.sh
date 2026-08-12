#!/bin/bash
# READ-ONLY supplement to backup-traefik: capture the Flux OCIRepository chart sources (so a durable
# revert knows exactly which chart/version manages traefik + infra), and probe the SERVED cert on a
# live instance host + the apex, to record the working-baseline evidence. NO writes to the cluster.
set +e
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP || exit 1
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
BK="$STATE/backup-traefik"; mkdir -p "$BK"
TO=/usr/bin/timeout
K(){ $TO 40 kubectl "$@" </dev/null; }
SUF="ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"

echo "===== A) Flux OCIRepository sources for traefik + infra -> flux-sources.yaml ====="
: > "$BK/flux-sources.yaml"
{
  echo "### OCIRepository traefik / traefik-crds / infra (platform-mesh-system)"
  for r in traefik traefik-crds infra; do
    echo "--- ocirepository platform-mesh-system/$r ---"
    K -n platform-mesh-system get ocirepository.source.toolkit.fluxcd.io "$r" -o yaml 2>/dev/null | grep -av memcache
  done
} >> "$BK/flux-sources.yaml" 2>&1
echo "flux-sources.yaml bytes=$(wc -c < "$BK/flux-sources.yaml")"
echo "--- source URLs (quick ref) ---"
K -n platform-mesh-system get ocirepository.source.toolkit.fluxcd.io 2>/dev/null | grep -av memcache

echo
echo "===== B) served-cert probe on a live instance host + apex (records WORKING baseline) -> served-cert-probe.txt ====="
: > "$BK/served-cert-probe.txt"
# pick a live instance host from the gateway HTTPRoutes hostnames, else use a known one
HOST="$(K -n platform-mesh-system get httproute -o jsonpath='{range .items[*]}{.spec.hostnames[0]}{"\n"}{end}' 2>/dev/null | grep -av memcache | grep -E "^[^*].*\.${SUF}$" | grep -iv keycloak | head -1)"
[ -n "$HOST" ] || HOST="my-aitrust.${SUF}"
{
  echo "probe time: $(date -u)  LB=130.214.18.166"
  for h in "$HOST" "$SUF"; do
    echo "=================================================================="
    echo "### SNI=$h  (connect via LB 130.214.18.166:443)"
    $TO 25 bash -c "echo | openssl s_client -connect 130.214.18.166:443 -servername '$h' 2>/dev/null \
      | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null" | head -10
  done
} >> "$BK/served-cert-probe.txt" 2>&1
cat "$BK/served-cert-probe.txt"

echo
echo "===== C) confirm no default-cert / file-provider on traefik (negative evidence) -> traefik-defaultcert-check.txt ====="
: > "$BK/traefik-defaultcert-check.txt"
{
  echo "### full traefik container args (search for defaultCertificate / providers.file / tlsStore):"
  K -n default get deploy traefik -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null | grep -av memcache
  echo
  echo "### grep for any default/tls/cert/file in args:"
  K -n default get deploy traefik -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null | grep -aiE 'default|tls|cert|file|store' || echo "(only --entryPoints.websecure.http.tls=true — NO defaultCertificate, NO providers.file)"
  echo
  echo "### volumes / volumeMounts (confirm NO cert secret mounted):"
  K -n default get deploy traefik -o jsonpath='{range .spec.template.spec.volumes[*]}vol {.name}={.secret.secretName}{.configMap.name}{"\n"}{end}' 2>/dev/null | grep -av memcache
} >> "$BK/traefik-defaultcert-check.txt" 2>&1
cat "$BK/traefik-defaultcert-check.txt"

echo
echo "===== DONE — supplement listing ====="
ls -la "$BK"
