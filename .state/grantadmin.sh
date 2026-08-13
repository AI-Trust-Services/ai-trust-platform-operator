#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MT_MSP
source scripts/lib.sh; load_config; export KUBECONFIG="$SHOOT_KUBECONFIG"
NS=aitrust-mt-msp; GWNS=platform-mesh-system
STOREID=01KZX8TV6TMMF3G3F9DTE87YV4
USER="mircea.craciun@sap.com"
echo "== grant user:$USER -> member -> role:platform_administrator in store $STOREID =="
kubectl -n "$NS" run g-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.9.1 --quiet --command -- \
  sh -c "
    B=http://openfga.$GWNS.svc.cluster.local:8080
    # write (idempotent-ish: ignore 'already exists')
    W=\$(curl -s -o /dev/null -w '%{http_code}' -X POST \$B/stores/$STOREID/write -H 'content-type: application/json' -d '{\"writes\":{\"tuple_keys\":[{\"user\":\"user:$USER\",\"relation\":\"member\",\"object\":\"role:platform_administrator\"}]}}')
    echo \"write http=\$W (200=ok, 400=already exists)\"
    echo '-- verify: can_manage_iam for this user (expect allowed:true) --'
    curl -s -X POST \$B/stores/$STOREID/check -H 'content-type: application/json' -d '{\"tuple_key\":{\"user\":\"user:$USER\",\"relation\":\"can_manage_iam\",\"object\":\"platform:global\"}}'
    echo
    echo '-- verify: can_write_systems (expect allowed:true) --'
    curl -s -X POST \$B/stores/$STOREID/check -H 'content-type: application/json' -d '{\"tuple_key\":{\"user\":\"user:$USER\",\"relation\":\"can_write_systems\",\"object\":\"platform:global\"}}'
    echo
  " 2>&1 | grep -avi memcache
echo DONE
