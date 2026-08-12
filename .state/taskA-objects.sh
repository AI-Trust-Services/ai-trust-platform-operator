#!/bin/bash
# TASK A part 2b (STRICT READ-ONLY — get/logs only, NO pod creation, NO port-forward):
# Confirm the cert-selection mechanism from the API objects that drive it.
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config 2>/dev/null
export KUBECONFIG="$STATE/shoot-kubeconfig.yaml"
G(){ grep -av memcache; }
SUF=ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu

echo "### HTTPRoutes attached to k8sapi-gateway: their hostnames (wildcard => HostRegexp router) ###"
kubectl get httproute -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}  hosts={.spec.hostnames}  parent={.spec.parentRefs[0].name}/{.spec.parentRefs[0].sectionName}{"\n"}{end}' 2>&1 | G | head -60
echo

echo "### Specifically: any HTTPRoute with a CONCRETE (non-wildcard) instance host? (would bind a cert) ###"
kubectl get httproute -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.hostnames}{"\n"}{end}' 2>&1 | G | grep -iE "aitrust|ai-trust" | head -40
echo

echo "### Re-confirm: NO TLSStore / TLSOption anywhere (traefik.io) ###"
kubectl get tlsstore,tlsoption -A 2>&1 | G | head
echo

echo "### Re-confirm traefik full startup log: is there a 'default certificate' / 'generating' line? (whole log, cert-only) ###"
POD="$(kubectl -n default get pods -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | G)"
kubectl -n default logs "$POD" 2>&1 | G | grep -iE 'default.?cert|self.?sign|generat|acme|certificate store|adding certificate|no certificate' | head -40
echo "(if empty above => traefik logs nothing about a default cert at INFO; it silently uses the built-in generated self-signed for unmatched SNI)"
echo

echo "### count of the 'No domain found in rule HostRegexp' warnings (the mechanism) ###"
kubectl -n default logs "$POD" 2>&1 | G | grep -c 'No domain found in rule HostRegexp'
echo

echo "### Does ANY HostSNI/Host (non-regex) router exist for terminate listeners? grep routerName w/ Host( ###"
kubectl -n default logs "$POD" 2>&1 | G | grep -iE 'Host\(' | grep -v 'HostRegexp' | head -20
echo "(non-HostRegexp Host() routers CAN bind the listener certRef; HostRegexp ones cannot)"
