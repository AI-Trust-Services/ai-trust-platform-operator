TASK D — READ-ONLY BACKUP of current working DNS / cert / routing config
Shoot: ai-trust-1   Project: garden-ai-trust   Gateway ns: platform-mesh-system
Captured: 2026-08-11 (garden login WAS valid this run; live `get` succeeded)
Scope: READ-ONLY. No apply/patch/delete/restart/scale was performed on any live resource.

====================================================================
WHAT EACH FILE IS (and how it was captured)
====================================================================
Live-captured this run (via minted shoot adminkubeconfig, `kubectl get ... -o yaml`):

  gateway.yaml               k8sapi-gateway (Gateway API, gatewayClassName=traefik), full YAML.
                             6 listeners: terminate, terminate-wildstar, passthrough,
                             terminate-services, terminate-aitrust, terminate-aitrust-wild.
                             5 of them (all but passthrough) tls.certificateRefs -> Secret
                             platform-mesh-system/domain-certificate.
                             `kubectl -n platform-mesh-system get gateway k8sapi-gateway -o yaml`

  secret.yaml                Secret platform-mesh-system/domain-certificate (type kubernetes.io/tls),
                             FULL bytes (tls.crt/tls.key/ca.crt) — KEPT intact, needed to restore.
                             This is the cluster's own TLS secret consumed by the gateway listeners.
                             `kubectl -n platform-mesh-system get secret domain-certificate -o yaml`

  httproutes.yaml            ALL HTTPRoutes in platform-mesh-system (list). Includes the AITrust /
                             per-instance routes AND the stock mesh routes. AITrust-relevant ones:
                               ai-trust-app, ai-trust-keycloak            (standalone app, sectionName terminate-aitrust)
                               aitp-25veqwflh7syq7fm-d-app / -keycloak     (MSP instance "d",  terminate-wildstar)
                               aitp-33hins0iklcwfg45-d-app / -keycloak     (MSP instance,       terminate-wildstar)
                               aitp-33hins0iklcwfg45-testai-app / -keycloak(MSP instance testai, terminate-wildstar)
                               aitp-q3c0weh7suf5hgjk-my-aitrust-app/-keycloak (MSP instance,     terminate-wildstar)
                             (stock, NOT AITrust: dex, iam-service, iam-ui, keycloak,
                              kubernetes-graphql-gateway, marketplace-ui, portal)
                             `kubectl -n platform-mesh-system get httproute -o yaml`

  dnsentries.yaml            dns.gardener.cloud/v1alpha1 DNSEntry list — EMPTY (items: []).
                             => NO per-host DNSEntry CRs exist today. Public DNS is served by the
                             shoot-dns wildcard A-record on the mesh gateway LB Service, NOT by DNSEntry CRs.
                             `kubectl get dnsentry -A -o yaml`

  gardener-certificates.yaml cert.gardener.cloud/v1alpha1 Certificate list (the CRs that matter here).
                             3 objects, all state=Ready, issuerRef name=gardener
                             (ns shoot--ai-trust--ai-trust-1 = the gardener control-plane issuer):
                               cert-p1            dnsNames: *.ai-trust-1.<suffix>              -> secret cert-p1
                               cert-p2            dnsNames: ai-trust-1.<suffix>                -> secret cert-p2
                               domain-certificate dnsNames: ai-trust-1.<suffix> + *.ai-trust-1.<suffix> -> secret domain-certificate
                             NOTE: NO kcp.api.* SAN here (that SAN lives only on the served leaf +
                             on cert-manager's internal kcp certs).
                             `kubectl get certificates.cert.gardener.cloud -A -o yaml`

  certificates.yaml          cert-manager.io/v1 Certificate list (all ns) — captured for completeness.
                             These are cert-manager objects (kcp/frontproxy internal PKI etc.), NOT the
                             gardener domain cert. The 4 ai-trust hits are kcp internal certs
                             (root-frontproxy-server, root-server) whose SAN includes kcp.api.<suffix>.
                             `kubectl get certificate -A -o yaml`   (matched the cert-manager CRD)

Supporting artifacts copied from repo / decoded earlier (context, not live cluster state):
  domain-certificate.leaf.crt / .ca.crt / .decoded.txt   decoded served leaf + local CA:
       leaf CN=ai-trust-1-mesh, issuer CN=Standard Platform Mesh Local CA (SELF-SIGNED),
       notBefore 2026-08-10, notAfter 2028-11-12, SAN = apex + *.ai-trust-1.<suffix> + kcp.api.ai-trust-1.<suffix>
  operator-wireIngress.snippet.go            operator routing model (ensureWildcardListener/wireIngress).
  gateway-listener-patch.tmpl, httproute.tmpl  repo templates the deploy uses.
  gardener-managed-dns-cert-reference.md / managed-dns-cert-reference.md / gardener-dns-proof-howto.md
  mesh-deploy3-prereq-and-cert-timeout.log   evidence of the earlier ACME/kcp.api cert timeout.
  TASK_A_FINDINGS.md / TASKB-FINDINGS.md / probe-evidence.txt  prior-phase analysis (some earlier
       assumptions about "static self-signed only" are refined by gardener-certificates.yaml above).

====================================================================
PROVENANCE — chart-managed vs operator-created vs manually-seeded
====================================================================
CHART-MANAGED (Helm release "infra" in platform-mesh-system; do NOT hand-edit — Helm/Flux will revert):
  - k8sapi-gateway  (annotations meta.helm.sh/release-name=infra, managed-by=Helm,
                     helm.toolkit.fluxcd.io/name=infra -> reconciled by Flux HelmRelease "infra").
  - stock HTTPRoutes: dex, iam-service, iam-ui, keycloak, kubernetes-graphql-gateway, marketplace-ui, portal.
  - gardener Certificates cert-p1 / cert-p2 (and domain-certificate) were `kubectl apply`-ed (they carry
    last-applied-configuration) as part of the mesh bring-up (prerequisites/deploy), issuerRef=gardener.

OPERATOR-CREATED (by the AITrust MSP operator, per instance; safe to let the operator re-stamp):
  - HTTPRoutes aitp-<consumerClusterId>-<name>-app  and  -keycloak  (sectionName terminate-wildstar).
  - The standalone app routes ai-trust-app / ai-trust-keycloak (sectionName terminate-aitrust) come from
    the Standard_Ai_Platform standalone deploy, not the MSP operator.
  - The operator's ensureWildcardListener only ADDS a terminate-wildstar listener if absent; the stock
    gateway already ships it, so today the operator does not own the listener.

MANUALLY-SEEDED (bootstrap, static):
  - Secret domain-certificate itself was `kubectl apply`-ed as a plain kubernetes.io/tls Secret
    (its last-applied-configuration is a bare Secret with literal tls.crt/tls.key/ca.crt — the
    self-signed CN=ai-trust-1-mesh material). It has NO ownerReference from the gardener Certificate,
    so the gardener Certificate "domain-certificate" is NOT currently overwriting these static bytes;
    the served cert stays the static self-signed leaf (notAfter matches: 2028-11-12).

====================================================================
HOW TO ROLL BACK (only if a later change breaks the working setup)
====================================================================
Prereq: valid garden login, then mint a shoot admin kubeconfig:
  cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
  # (login first if expired) bash prerequisites/login.sh
  # lib.sh mints .state/shoot-kubeconfig.yaml automatically via `sk`; or reuse:
  export KUBECONFIG=.state/shoot-kubeconfig.yaml
  BK=.state/backup-dnscert

1) Restore the TLS secret (static self-signed material the gateway serves):
     kubectl apply -f "$BK/secret.yaml"
   (Apply BEFORE the gateway so listeners find their certificateRefs target.)

2) Restore the gateway (repoints all 5 listeners back to domain-certificate):
     kubectl apply -f "$BK/gateway.yaml"
   NOTE: k8sapi-gateway is Helm/Flux-managed (release "infra"). A hand `apply` restores the desired
   state immediately, but the authoritative fix is to revert the change in the "infra" HelmRelease
   values/chart so Flux does not reconcile your rollback away. If you only changed a listener's
   certificateRefs at runtime, `kubectl apply -f gateway.yaml` is enough to get back to today's state.

3) Restore the AITrust HTTPRoutes (only the ones you touched):
     kubectl apply -f "$BK/httproutes.yaml"
   This file is the FULL platform-mesh-system HTTPRoute list. To restore just the AITrust/MSP routes,
   apply selectively (the operator will also re-create the aitp-* routes on the next reconcile if deleted):
     ai-trust-app, ai-trust-keycloak,
     aitp-25veqwflh7syq7fm-d-app/-keycloak, aitp-33hins0iklcwfg45-d-app/-keycloak,
     aitp-33hins0iklcwfg45-testai-app/-keycloak, aitp-q3c0weh7suf5hgjk-my-aitrust-app/-keycloak.

4) Restore the gardener Certificate CRs (if a later change deleted/edited them):
     kubectl apply -f "$BK/gardener-certificates.yaml"
   (Recreates cert-p1, cert-p2, domain-certificate as cert.gardener.cloud/v1alpha1, issuerRef=gardener.)

5) DNSEntry: none existed (dnsentries.yaml is empty). If a later change ADDED DNSEntry/Certificate CRs
   for managed DNS/cert and you need to get back to today, DELETE only the objects you added — there is
   nothing to re-apply here. Do NOT delete the shoot-dns wildcard record source (the gateway LB Service
   annotation) — that is what serves *.ai-trust-1.<suffix> today.

Sanity checks after rollback (all read-only):
  kubectl -n platform-mesh-system get gateway k8sapi-gateway \
    -o jsonpath='{range .spec.listeners[*]}{.name}{" certRefs="}{.tls.certificateRefs[*].name}{"\n"}{end}'
  kubectl -n platform-mesh-system get secret domain-certificate -o jsonpath='{.type}{"\n"}'
  # external: served cert should be CN=ai-trust-1-mesh (self-signed) and each host should 200 behind oauth2-proxy
  echo | openssl s_client -connect 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu:443 \
    -servername 25veqwflh7syq7fm-d.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu 2>/dev/null \
    | openssl x509 -noout -subject -issuer

suffix = ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
