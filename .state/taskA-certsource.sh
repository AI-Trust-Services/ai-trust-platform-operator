#!/bin/bash
# TASK A (READ-ONLY): determine EXACTLY how Traefik picks the cert it serves on :8443.
# No apply/patch/edit/delete/restart. Only get/logs/exec-read/curl-inside-cluster.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config 2>/dev/null
export KUBECONFIG="$STATE/shoot-kubeconfig.yaml"
NS=platform-mesh-system; SUF=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
G(){ grep -av memcache; }

echo "### 0. garden/shoot reachability (fast, no interactive mint) ###"
kubectl get ns default -o name 2>&1 | G | head -1
echo

echo "### 1. traefik pod name ###"
POD="$(kubectl -n default get pods -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | G)"
echo "POD=$POD"
echo

echo "### 2. FULL traefik args (authoritative, live) ###"
kubectl -n default get pod "$POD" -o jsonpath='{range .spec.containers[0].args[*]}{@}{"\n"}{end}' 2>&1 | G
echo

echo "### 3. env of traefik container (look for TRAEFIK_* / ACME / default cert) ###"
kubectl -n default get pod "$POD" -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>&1 | G
echo

echo "### 4. volume mounts + volumes (any secret/configmap = file provider or default cert?) ###"
kubectl -n default get pod "$POD" -o jsonpath='{range .spec.containers[0].volumeMounts[*]}mount {.name} -> {.mountPath} ro={.readOnly}{"\n"}{end}' 2>&1 | G
kubectl -n default get pod "$POD" -o jsonpath='{range .spec.volumes[*]}vol {.name} secret={.secret.secretName} cm={.configMap.name}{"\n"}{end}' 2>&1 | G
echo

echo "### 5. traefik STARTUP logs — TLS/cert/store/default/gateway/acme lines ###"
kubectl -n default logs "$POD" --tail=4000 2>&1 | G | grep -iE 'tls|cert|store|default|acme|gateway|self.?signed|generat' | head -60
echo
echo "### 5b. any WARN/ERROR lines at all ###"
kubectl -n default logs "$POD" --tail=4000 2>&1 | G | grep -iE '"level":"(warn|error)"|level=warn|level=error' | head -40
