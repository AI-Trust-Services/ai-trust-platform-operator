#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
export KUBECONFIG="$SHOOT_KUBECONFIG"
exec > .state/inv2-pod.out 2>&1
K(){ kubectl "$@" 2>&1 | grep -avi memcache; }

POD=root-kcp-565c99f9dc-gdg78

echo "############ root-kcp pod: container args ############"
K -n "$MESH_NS" get pod $POD -o jsonpath='{range .spec.containers[*]}CONTAINER={.name}{"\n"}{range .args[*]}  ARG={@}{"\n"}{end}{end}'

echo; echo "############ root-kcp pod: volumeMounts ############"
K -n "$MESH_NS" get pod $POD -o jsonpath='{range .spec.containers[*].volumeMounts[*]}MOUNT={.name} -> {.mountPath} (ro={.readOnly}){"\n"}{end}'

echo; echo "############ root-kcp pod: volumes (secrets/configmaps) ############"
K -n "$MESH_NS" get pod $POD -o jsonpath='{range .spec.volumes[*]}VOL={.name} secret={.secret.secretName} cm={.configMap.name} proj={.projected.sources}{"\n"}{end}'

echo; echo "############ root-kcp pod: env with oidc/auth/ca ############"
K -n "$MESH_NS" get pod $POD -o yaml | grep -iE 'oidc|issuer|authentication|ca-file|ca-bundle|--oidc' | grep -avi managedFields
