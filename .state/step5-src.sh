#!/bin/bash
exec > /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP/.state/step5-src.out 2>&1
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
[ -s "$SHOOT_KUBECONFIG" ] || mint_shoot_kubeconfig || { echo LOGIN_EXPIRED; exit 3; }
GWNS=platform-mesh-system

echo "############ 1. account-operator deploy: args/env/mounts — where does it read the WAC CA from? ############"
AO=$(kubectl -n "$GWNS" get deploy -o name 2>/dev/null | grep -avi memcache | grep -iE 'account-operator' | head -1)
echo "deploy: $AO"
kubectl -n "$GWNS" get "$AO" -o jsonpath='{range .spec.template.spec.containers[*]}ARGS={.args}{"\n"}ENV={range .env[*]}{.name}={.value};{end}{"\n"}{end}' 2>&1 | grep -avi memcache | tr ';' '\n' | grep -iE 'ca|cert|issuer|oidc|keycloak|trust|secret|domain' | head -20
echo "-- volumes/mounts --"
kubectl -n "$GWNS" get "$AO" -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{" secret="}{.secret.secretName}{" cm="}{.configMap.name}{"\n"}{end}' 2>&1 | grep -avi memcache

echo
echo "############ 2. account-operator HelmRelease values (the durable knob) ############"
kubectl -n "$GWNS" get helmrelease account-operator -o jsonpath='{.spec.values}' 2>&1 | grep -avi memcache | tr ',' '\n' | grep -iE 'ca|cert|issuer|oidc|keycloak|trust|domain|authentication' | head -20 || echo "  (no account-operator HR or no matching values)"
echo "-- list all helmreleases to find the right one --"
kubectl -n "$GWNS" get helmrelease 2>&1 | grep -avi memcache | head -20

echo
echo "############ 3. does the account-operator read domain-certificate-ca (which we already updated)? ############"
kubectl -n "$GWNS" get "$AO" -o yaml 2>&1 | grep -avi memcache | grep -iE 'domain-certificate|domain-ca|caSecret|ca-secret' | head

echo
echo "############ 4. HOW is the WAC CA templated? Check a config/template the operator uses ############"
kubectl -n "$GWNS" get cm 2>&1 | grep -avi memcache | grep -iE 'account|onboard|workspace|template' | head
echo DONE
