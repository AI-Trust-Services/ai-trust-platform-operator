#!/bin/bash
# ============================================================================
# TASK B — READ-ONLY SNI/port cert matrix.
# Goal: determine whether Traefik serves ONE default cert for ALL SNI (=> listener
#       certRefs are irrelevant, fix the DEFAULT cert), or a per-listener cert
#       (=> certRef works, earlier trial had another cause).
# Also: does LB expose :443 and :8443 with different TLS behaviour?
# STRICTLY READ-ONLY: only get/describe + curl/openssl probes from a throwaway pod.
# The probe pod uses --rm (auto-deletes); it makes NO change to any live resource.
# ============================================================================
set -uo pipefail
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=platform-mesh-system
BK=".state/backup-taskB"; mkdir -p "$BK"
K(){ kubectl "$@" 2>&1 | grep -av memcache; }

echo "############ 0. BACKUP (read-only snapshot of the resources under study) ############"
K -n "$NS" get gateway "$GATEWAY_NAME" -o yaml > "$BK/gateway.yaml"
K -n default get deploy traefik -o yaml   > "$BK/traefik-deploy.yaml"
K -n default get svc traefik -o yaml      > "$BK/traefik-svc.yaml"
K get tlsstore -A -o yaml                 > "$BK/tlsstore-all.yaml" 2>/dev/null
K -n "$NS" get secret cert-p1 -o yaml     > "$BK/secret-cert-p1.yaml"
K -n "$NS" get secret domain-certificate -o yaml > "$BK/secret-domain-certificate.yaml"
echo "backed up to $BK:"; ls -la "$BK"

echo
echo "############ 1. GATEWAY LISTENERS: name | port | protocol | hostname | certRef ############"
kubectl -n "$NS" get gateway "$GATEWAY_NAME" -o json 2>/dev/null | grep -av memcache \
| python3 -c '
import sys,json
g=json.load(sys.stdin)
for l in g["spec"]["listeners"]:
    tls=l.get("tls",{})
    refs=",".join(r.get("name","?") for r in tls.get("certificateRefs",[])) or "-"
    print(f'"'"'  {l["name"]:<22} port={l.get("port")}  proto={l.get("protocol"):<6} host={l.get("hostname","-"):<60} certRef={refs}'"'"')
print()
print("  --- listener status (Programmed / ResolvedRefs) ---")
for l in g.get("status",{}).get("listeners",[]):
    conds={c["type"]:c["status"] for c in l.get("conditions",[])}
    print(f'"'"'  {l["name"]:<22} Programmed={conds.get("Programmed","?"):<5} ResolvedRefs={conds.get("ResolvedRefs","?"):<5} Accepted={conds.get("Accepted","?")}'"'"')
'

echo
echo "############ 2. LB SERVICE PORTS (what :443 and :8443 map to) ############"
kubectl -n default get svc traefik -o json 2>/dev/null | grep -av memcache \
| python3 -c '
import sys,json
s=json.load(sys.stdin)
print("  EXTERNAL-IP:", [i.get("ip") for i in s.get("status",{}).get("loadBalancer",{}).get("ingress",[])])
print("  name       port  targetPort  protocol")
for p in s["spec"]["ports"]:
    print(f'"'"'  {p.get("name","-"):<10} {p.get("port"):<5} {str(p.get("targetPort")):<11} {p.get("protocol")}'"'"')
'
echo "  --- traefik entryPoint args (which :port has http.tls, and any default cert) ---"
kubectl -n default get deploy traefik -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 \
  | grep -av memcache | grep -iE 'entrypoint|tls|cert|default' | sed 's/^/    /'
echo "  --- traefik volumes (any default-cert secret mounted?) ---"
kubectl -n default get deploy traefik -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}={.secret.secretName}{"\n"}{end}' 2>&1 \
  | grep -av memcache | sed 's/^/    /'

echo
echo "############ 3. SNI x PORT CERT MATRIX (from a throwaway curl pod) ############"
LB=130.214.18.166
SUF="$INSTANCE_DOMAIN_SUFFIX"
# Instance hosts (from prior probes), apex, and a *.services host.
INST_A="25veqwflh7syq7fm-d.$SUF"
INST_B="testai.$SUF"
APEX="portal.$SUF"
BARE="$SUF"
SVC="foo.services.$SUF"
RAND="doesnotexist-probe.$SUF"

# Build a small script that runs INSIDE the pod: for each (port,sni) print served issuer+subject.
read -r -d '' INPOD <<'EOS'
probe() {
  port="$1"; sni="$2"
  out=$(echo | timeout 12 openssl s_client -connect 130.214.18.166:${port} -servername "${sni}" 2>/dev/null \
        | openssl x509 -noout -subject -issuer -dates 2>/dev/null)
  if [ -z "$out" ]; then
    echo "  port=${port} sni=${sni}  -> NO CERT / handshake failed"
  else
    subj=$(echo "$out" | sed -n 's/^subject=//p' | tr -d '\n')
    iss=$(echo  "$out" | sed -n 's/^issuer=//p'  | tr -d '\n')
    naft=$(echo "$out" | sed -n 's/^notAfter=//p')
    echo "  port=${port} sni=${sni}"
    echo "       subject: ${subj}"
    echo "       issuer : ${iss}"
    echo "       expires: ${naft}"
  fi
}
EOS

# hosts passed as env into pod
HOSTS_ENV="INST_A=$INST_A INST_B=$INST_B APEX=$APEX BARE=$BARE SVC=$SVC RAND=$RAND"

kubectl -n "$NS" run tbmatrix-$RANDOM --rm -i --restart=Never --image=alpine/openssl:latest --quiet \
  --env="INST_A=$INST_A" --env="INST_B=$INST_B" --env="APEX=$APEX" \
  --env="BARE=$BARE" --env="SVC=$SVC" --env="RAND=$RAND" \
  --command -- sh -c "
$INPOD
for P in 443 8443; do
  echo '===== PORT '\$P' ====='
  for VAR in INST_A INST_B APEX BARE SVC RAND; do
    eval H=\\\$\$VAR
    echo \"-- \$VAR = \$H --\"
    probe \$P \"\$H\"
  done
done
" 2>&1 | grep -av memcache

echo
echo "############ 4. curl trust check (does a real public CA trust what's served on :443?) ############"
kubectl -n "$NS" run tbcurl-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet \
  -- sh -c "
for H in $INST_A $INST_B $APEX; do
  echo \"-- \$H :443 --\"
  curl -sS -o /dev/null -w 'http=%{http_code} ssl_verify=%{ssl_verify_result}\n' --resolve \$H:443:$LB https://\$H/ 2>&1 | head -2
  echo \"-- \$H :8443 --\"
  curl -sS -o /dev/null -w 'http=%{http_code} ssl_verify=%{ssl_verify_result}\n' --resolve \$H:8443:$LB https://\$H:8443/ 2>&1 | head -2
done
" 2>&1 | grep -av memcache

echo
echo "############ DONE ############"
