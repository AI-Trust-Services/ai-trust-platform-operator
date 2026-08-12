#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
source scripts/lib.sh; load_config
NS=aitp-33hins0iklcwfg45-d
echo "=== oauth2-proxy pods (only the patched one should remain) + cookie secure setting ==="
sk -n "$NS" get pods 2>&1 | grep -av memcache | grep oauth2-proxy
POD=$(sk -n "$NS" get pods 2>/dev/null | grep -av memcache | grep oauth2-proxy | grep Running | awk '{print $1}' | tail -1)
sk -n "$NS" logs "$POD" 2>&1 | grep -av memcache | grep -iE 'Cookie settings' | tail -1
echo "=== any NOT-ready deploy (why CR still Provisioning)? ==="
sk -n "$NS" get deploy --no-headers 2>&1 | grep -av memcache | awk '$2!="1/1"{print "NOT READY:",$1,$2}'; echo "(nothing above = all ready)"
echo "=== rabbitmq probe (the usual straggler) ==="
sk -n "$NS" get deploy rabbitmq -o jsonpath='rabbitmq {.status.availableReplicas}/{.spec.replicas} probeTimeout={.spec.template.spec.containers[0].readinessProbe.timeoutSeconds}{"\n"}' 2>&1 | grep -av memcache
echo "=== operator: is it still reconciling d? (it may be wedged like before) ==="
sk -n aitrust-msp logs deploy/aitrust-msp-operator --tail=15 2>&1 | grep -av memcache | grep -iE 'reconcile|"d"|Ready|error' | grep -ivE 'controller-runtime@|/src/main|sigs.k8s' | tail -6
