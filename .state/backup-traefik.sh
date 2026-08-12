#!/bin/bash
# READ-ONLY backup of the Traefik data plane + gateway + certs so we can always return to
# today's WORKING self-signed setup. NO apply/patch/edit/delete/restart/scale/rollout.
# Only get/describe/logs. Writes LOCAL files under .state/backup-traefik/.
set +e
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP || exit 1
source scripts/lib.sh
load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
BK="$STATE/backup-traefik"; mkdir -p "$BK"
TO=/usr/bin/timeout
K(){ $TO 40 kubectl "$@" </dev/null; }

echo "===== STEP 0: kubeconfig present + reachability probe (30s cap) ====="
ls -la "$SHOOT_KUBECONFIG" 2>&1 | head -1
probe="$($TO 30 kubectl get ns platform-mesh-system -o name </dev/null 2>&1)"
prc=$?
echo "probe-rc=$prc out=$(echo "$probe" | grep -av memcache | head -1)"
if [ "$prc" -eq 124 ]; then
  echo "RESULT=SHOOT_UNREACHABLE_TIMEOUT (cached kubeconfig likely expired; garden login needed)"
  echo "Proceeding to attempt each capture with hard caps; partial backup only."
fi

echo
echo "===== STEP 1: deployment default/traefik  -> traefik-deploy.yaml ====="
K -n default get deploy traefik -o yaml > "$BK/traefik-deploy.yaml" 2>"$BK/traefik-deploy.err"
echo "rc=$? bytes=$(wc -c < "$BK/traefik-deploy.yaml" 2>/dev/null)"
grep -av memcache "$BK/traefik-deploy.err" 2>/dev/null | head -3
echo "--- args (for quick reference) ---"
K -n default get deploy traefik -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null | grep -av memcache
echo "--- volumes (name=secret/configmap) ---"
K -n default get deploy traefik -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}={.secret.secretName}{.configMap.name}{"\n"}{end}' 2>/dev/null | grep -av memcache
echo "--- volumeMounts (container 0) ---"
K -n default get deploy traefik -o jsonpath='{range .spec.template.spec.containers[0].volumeMounts[*]}{.name}@{.mountPath}{"\n"}{end}' 2>/dev/null | grep -av memcache

echo
echo "===== STEP 2: Service default/traefik -> traefik-svc.yaml ====="
K -n default get svc traefik -o yaml > "$BK/traefik-svc.yaml" 2>"$BK/traefik-svc.err"
echo "rc=$? bytes=$(wc -c < "$BK/traefik-svc.yaml" 2>/dev/null)"
grep -av memcache "$BK/traefik-svc.err" 2>/dev/null | head -3

echo
echo "===== STEP 3: traefik.io dynamic-config CRs across ALL namespaces ====="
: > "$BK/traefik-crs.yaml"
FOUND_CR=0
for kind in tlsstore tlsoption middleware ingressroute ingressroutetcp ingressrouteudp serverstransport serverstransporttcp traefikservice middlewaretcp; do
  n="$(K get "$kind" -A -o name 2>/dev/null | grep -av memcache | grep -c .)"
  echo "--- $kind: ${n:-0} object(s) ---" | tee -a "$BK/traefik-crs.yaml"
  if [ "${n:-0}" -gt 0 ]; then
    FOUND_CR=1
    K get "$kind" -A -o yaml 2>/dev/null | grep -av memcache >> "$BK/traefik-crs.yaml"
  fi
done
[ "$FOUND_CR" -eq 0 ] && echo "NONE: no traefik.io dynamic-config CRs of any listed kind exist." | tee -a "$BK/traefik-crs.yaml"
echo "traefik-crs.yaml bytes=$(wc -c < "$BK/traefik-crs.yaml" 2>/dev/null)"

echo
echo "===== STEP 4: ConfigMaps the traefik deployment references -> traefik-cm.yaml ====="
: > "$BK/traefik-cm.yaml"
CMNAMES="$(K -n default get deploy traefik -o jsonpath='{range .spec.template.spec.volumes[*]}{.configMap.name}{"\n"}{end}' 2>/dev/null | grep -av memcache | grep -v '^$' | sort -u)"
echo "configMap volumes referenced: ${CMNAMES:-<none>}"
if [ -n "$CMNAMES" ]; then
  for cm in $CMNAMES; do
    echo "--- configmap default/$cm ---" >> "$BK/traefik-cm.yaml"
    K -n default get cm "$cm" -o yaml 2>/dev/null | grep -av memcache >> "$BK/traefik-cm.yaml"
  done
else
  echo "No configMap volumes on the traefik deployment." >> "$BK/traefik-cm.yaml"
  echo "--- (context) all configmaps in ns default with traefik/tls in name ---" >> "$BK/traefik-cm.yaml"
  K -n default get cm 2>/dev/null | grep -av memcache | grep -iE 'traefik|tls|default' >> "$BK/traefik-cm.yaml" 2>/dev/null
fi
echo "traefik-cm.yaml bytes=$(wc -c < "$BK/traefik-cm.yaml" 2>/dev/null)"

echo
echo "===== STEP 5: gateway platform-mesh-system/k8sapi-gateway -> gateway.yaml ====="
K -n "$GATEWAY_NS" get gateway "$GATEWAY_NAME" -o yaml > "$BK/gateway.yaml" 2>"$BK/gateway.err"
echo "rc=$? bytes=$(wc -c < "$BK/gateway.yaml" 2>/dev/null)"
grep -av memcache "$BK/gateway.err" 2>/dev/null | head -3

echo
echo "===== STEP 6: secrets domain-certificate + cert-p1 (FULL bytes) -> secrets.yaml ====="
: > "$BK/secrets.yaml"
echo "# platform-mesh-system/domain-certificate + cert-p1 — full bytes for exact restore" >> "$BK/secrets.yaml"
echo "---" >> "$BK/secrets.yaml"
K -n "$GATEWAY_NS" get secret domain-certificate -o yaml 2>/dev/null | grep -av memcache >> "$BK/secrets.yaml"
echo "---" >> "$BK/secrets.yaml"
K -n "$GATEWAY_NS" get secret cert-p1 -o yaml 2>/dev/null | grep -av memcache >> "$BK/secrets.yaml"
echo "secrets.yaml bytes=$(wc -c < "$BK/secrets.yaml" 2>/dev/null)"
echo "--- cert identity (issuer/subject/dates/SAN) ONLY — no key bytes printed ---"
for s in domain-certificate cert-p1; do
  echo "### secret $s"
  K -n "$GATEWAY_NS" get secret "$s" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | grep -av memcache | base64 -d 2>/dev/null \
    | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null | head -8
done

echo
echo "===== STEP 7: Traefik Helm/Flux provenance -> traefik-helm-provenance.txt ====="
: > "$BK/traefik-helm-provenance.txt"
{
  echo "### deployment default/traefik metadata (labels + annotations reveal Helm/Flux ownership)"
  K -n default get deploy traefik -o jsonpath='{.metadata.labels}{"\n"}{.metadata.annotations}{"\n"}' 2>/dev/null | grep -av memcache
  echo
  echo "### Helm release annotations on the traefik svc"
  K -n default get svc traefik -o jsonpath='{.metadata.annotations}{"\n"}' 2>/dev/null | grep -av memcache
  echo
  echo "### HelmReleases (flux helm.toolkit.fluxcd.io) across all ns (name/ns/chart)"
  K get helmrelease.helm.toolkit.fluxcd.io -A 2>/dev/null | grep -av memcache
  echo
  echo "### HelmCharts / HelmRepositories (flux source) across all ns"
  K get helmchart.source.toolkit.fluxcd.io -A 2>/dev/null | grep -av memcache
  K get helmrepository.source.toolkit.fluxcd.io -A 2>/dev/null | grep -av memcache
  echo
  echo "### GitRepository / Kustomization (flux) across all ns"
  K get gitrepository.source.toolkit.fluxcd.io -A 2>/dev/null | grep -av memcache
  K get kustomization.kustomize.toolkit.fluxcd.io -A 2>/dev/null | grep -av memcache
  echo
  echo "### Helm secrets (sh.helm.release.v1.*) in ns default + platform-mesh-system (names only)"
  K -n default get secret 2>/dev/null | grep -av memcache | grep 'helm.release'
  K -n platform-mesh-system get secret 2>/dev/null | grep -av memcache | grep 'helm.release'
  echo
  echo "### traefik-managing HelmRelease full YAML (if a release named traefik/infra exists)"
  for rel in traefik infra; do
    for ns in default platform-mesh-system flux-system kube-system; do
      if K -n "$ns" get helmrelease.helm.toolkit.fluxcd.io "$rel" -o name >/dev/null 2>&1; then
        echo "--- helmrelease $ns/$rel ---"
        K -n "$ns" get helmrelease.helm.toolkit.fluxcd.io "$rel" -o yaml 2>/dev/null | grep -av memcache
      fi
    done
  done
} >> "$BK/traefik-helm-provenance.txt" 2>&1
echo "traefik-helm-provenance.txt bytes=$(wc -c < "$BK/traefik-helm-provenance.txt" 2>/dev/null)"

echo
echo "===== DONE — backup dir listing ====="
ls -la "$BK"
