#!/bin/bash
# TASK B supplement — reconcile the "TRAEFIK DEFAULT CERT" served leaf vs the secrets.
# Dump the FULL served chain (all certs in the handshake) for one instance host on :443 and :8443,
# and decode the CN/issuer of domain-certificate and cert-p1 secrets locally. READ-ONLY.
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=platform-mesh-system; LB=130.214.18.166
SUF="$INSTANCE_DOMAIN_SUFFIX"; HOST="testai.$SUF"

echo "=== FULL served chain on :443 (SNI=$HOST) — every cert offered in the handshake ==="
kubectl -n "$NS" run tbchain-$RANDOM --rm -i --restart=Never --image=alpine/openssl:latest --quiet \
  --command -- sh -c "echo | openssl s_client -connect $LB:443 -servername $HOST -showcerts 2>/dev/null \
    | awk '/BEGIN CERT/{c++} {print > \"/tmp/c\"c}'; \
    for f in /tmp/c*; do [ -s \"\$f\" ] || continue; echo \"---- chain member \$f ----\"; \
      openssl x509 -in \"\$f\" -noout -subject -issuer 2>/dev/null; done" 2>&1 | grep -av memcache

echo
echo "=== domain-certificate secret leaf: subject/issuer/SAN (decoded from backup) ==="
python3 - "$NS" <<'PY' 2>&1 | grep -av memcache
import base64,subprocess,sys,yaml
f=".state/backup-taskB/secret-domain-certificate.yaml"
d=yaml.safe_load(open(f))
crt=base64.b64decode(d["data"]["tls.crt"])
p=subprocess.run(["openssl","x509","-noout","-subject","-issuer","-ext","subjectAltName"],input=crt,capture_output=True)
print(p.stdout.decode(errors="replace"))
print(p.stderr.decode(errors="replace"))
PY

echo "=== cert-p1 secret leaf: subject/issuer/SAN/dates (the REAL LE wildcard) ==="
python3 - <<'PY' 2>&1 | grep -av memcache
import base64,subprocess,yaml
d=yaml.safe_load(open(".state/backup-taskB/secret-cert-p1.yaml"))
crt=base64.b64decode(d["data"]["tls.crt"])
p=subprocess.run(["openssl","x509","-noout","-subject","-issuer","-dates","-ext","subjectAltName"],input=crt,capture_output=True)
print(p.stdout.decode(errors="replace"))
PY

echo "=== Does traefik run with an explicit default-cert / tls.stores config we missed? full arg list ==="
kubectl -n default get deploy traefik -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | grep -av memcache | sed 's/^/  /'
echo "=== traefik providers.file or extra config volumes / configmaps mounted? ==="
kubectl -n default get deploy traefik -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}={.configMap.name}{.secret.secretName}{"\n"}{end}' 2>&1 | grep -av memcache | sed 's/^/  /'
echo "=== any TLSOption / ServersTransport / traefik CRDs present? ==="
kubectl get crd 2>&1 | grep -av memcache | grep -i traefik | sed 's/^/  /'
