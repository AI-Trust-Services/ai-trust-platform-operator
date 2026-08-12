READ-ONLY BACKUP — Traefik data plane + gateway + certs (return-to-working-self-signed)
=======================================================================================
Shoot:   ai-trust-1        Project: garden-ai-trust
Gateway: platform-mesh-system/k8sapi-gateway   (Gateway API, gatewayClassName=traefik)
Data plane: deployment default/traefik  (Helm release "traefik" ns default, chart traefik@39.0.7)
Captured: 2026-08-11 (garden login VALID this run; every live `get` returned rc=0)
SCOPE:   STRICTLY READ-ONLY. No apply/patch/edit/delete/restart/scale/rollout was performed on any
         live resource. Only `kubectl get -o yaml/jsonpath` and openssl s_client probes were used.

Backup produced by (both READ-ONLY, re-runnable):
  .state/backup-traefik.sh        (steps 1-7 below)
  .state/backup-traefik-supp.sh   (flux sources + served-cert probe + default-cert negative check)


====================================================================
FILES IN THIS DIRECTORY (.state/backup-traefik/)
====================================================================
traefik-deploy.yaml            (5161 B) deployment default/traefik — FULL YAML incl args, volumes,
                               volumeMounts. KEY FACTS captured:
                                 - entryPoint websecure = :8443/tcp ; --entryPoints.websecure.http.tls=true
                                 - providers: kubernetescrd + kubernetesingress + kubernetesgateway
                                   (experimentalChannel=true), statusaddress svc=default/traefik
                                 - NO --providers.file, NO --*.defaultCertificate, NO tlsStore arg
                                 - volumes ONLY: data(emptyDir) + tmp(emptyDir). NO cert secret mounted.
                               Source: kubectl -n default get deploy traefik -o yaml
traefik-deploy.err             empty (no error)

traefik-svc.yaml               (1799 B) Service default/traefik (LoadBalancer, EXTERNAL-IP 130.214.18.166,
                               ports 80/8443/443, clusterIP 100.104.188.4). Carries the gardener DNS
                               annotations that publish the public A-records:
                                 dns.gardener.cloud/class=garden
                                 dns.gardener.cloud/dnsnames=<apex>,*.<suffix>
                               Source: kubectl -n default get svc traefik -o yaml
traefik-svc.err                empty

traefik-crs.yaml               (1542 B) ALL traefik.io/v1alpha1 dynamic-config CRs across ALL namespaces,
                               probed for: tlsstore, tlsoption, middleware, ingressroute(+tcp/udp),
                               serverstransport(+tcp), traefikservice, middlewaretcp.
                               RESULT: only ONE object exists — Middleware platform-mesh-system/cors-header
                               (Helm release "infra"). NO TLSStore, NO TLSOption, NO IngressRoute anywhere.
                               => Confirms there is NO traefik.io default-cert store overriding the served cert.
                               Source: kubectl get <kind> -A -o yaml  (per kind)

traefik-cm.yaml                (120 B) ConfigMaps the traefik deployment mounts/references.
                               RESULT: the deployment references NO configMap volumes (only data+tmp
                               emptyDirs) — so there is no file-provider ConfigMap driving TLS.
                               Source: derived from deploy volumes; then kubectl -n default get cm <name> -o yaml

gateway.yaml                   (7409 B) platform-mesh-system/k8sapi-gateway — FULL YAML incl status.
                               6 listeners: terminate, terminate-wildstar, passthrough, terminate-services,
                               terminate-aitrust, terminate-aitrust-wild. All HTTPS-terminate listeners'
                               tls.certificateRefs -> Secret platform-mesh-system/domain-certificate.
                               Managed by Helm release "infra" (see provenance).
                               Source: kubectl -n platform-mesh-system get gateway k8sapi-gateway -o yaml
gateway.err                    empty

secrets.yaml                   (32334 B) FULL bytes of BOTH secrets (for exact restore):
                                 platform-mesh-system/domain-certificate (type kubernetes.io/tls) —
                                   the STATIC SELF-SIGNED material actually served today:
                                   subject CN=ai-trust-1-mesh, issuer CN=Standard Platform Mesh Local CA,
                                   notBefore 2026-08-10, notAfter 2028-11-12,
                                   SAN = <apex> + *.<suffix> + kcp.api.<suffix>
                                 platform-mesh-system/cert-p1 (type kubernetes.io/tls) —
                                   the REAL managed Let's Encrypt WILDCARD we WANT to serve:
                                   subject CN=*.<suffix>, issuer C=US O=Let's Encrypt CN=YR1,
                                   notBefore 2026-08-10, notAfter 2026-11-08, SAN = *.<suffix>
                               Source: kubectl -n platform-mesh-system get secret <name> -o yaml
                               (No private-key bytes were printed to the console — only issuer/subject/
                                dates/SAN were echoed; full bytes live only inside this file.)

traefik-helm-provenance.txt    (20291 B) Ownership map — the single most important file for a DURABLE change.
                               Contents:
                                 - deploy labels: managed-by=Helm, helm.sh/chart=traefik-39.0.7,
                                   helm.toolkit.fluxcd.io/name=traefik / namespace=platform-mesh-system
                                 - svc annotations: meta.helm.sh/release-name=traefik (ns default)
                                 - ALL Flux HelmReleases (25) — traefik + infra are the relevant two
                                 - Helm release secrets (sh.helm.release.v1.*) incl traefik v56..v60, infra v1..v3
                                 - FULL YAML of HelmRelease platform-mesh-system/traefik AND
                                   HelmRelease platform-mesh-system/infra (its .spec.values.gatewayApi.listeners
                                   is where the certificateRefs -> domain-certificate live).
                               Source: kubectl get helmrelease -A / get deploy,svc -o jsonpath / get helmrelease -o yaml

flux-sources.yaml              (7369 B) Flux OCIRepository sources (chart provenance). Relevant:
                                 traefik      oci://ghcr.io/platform-mesh/ocm/charts/traefik   39.0.7@sha256:a021f37d...
                                 traefik-crds oci://ghcr.io/platform-mesh/ocm/charts/traefik-crds 1.14.0@sha256:d7737018...
                                 infra        oci://ghcr.io/platform-mesh/helm-charts/infra    0.34.0@sha256:63e8ca2f...
                               Source: kubectl -n platform-mesh-system get ocirepository <name> -o yaml

served-cert-probe.txt          (1211 B) WORKING-BASELINE evidence — what is actually served today.
                               Probed LB 130.214.18.166:443 with SNI = a live instance host AND the apex;
                               BOTH return CN=ai-trust-1-mesh / issuer "Standard Platform Mesh Local CA"
                               (the self-signed domain-certificate). This is the state to preserve.
                               Source: openssl s_client -connect 130.214.18.166:443 -servername <host>

traefik-defaultcert-check.txt  (1214 B) Negative evidence: full traefik args + a grep proving there is
                               NO --*.defaultCertificate, NO --providers.file, NO tlsStore arg, and NO
                               cert secret volume — only --entryPoints.websecure.http.tls=true.


====================================================================
WHERE THE SERVED CERT ACTUALLY COMES FROM (why the Phase-2 certRef repoint failed)
====================================================================
- Traefik here runs with --providers.kubernetesgateway (experimental channel). For a Gateway API HTTPS
  listener, Traefik loads the cert from the listener's tls.certificateRefs. ALL terminate listeners on
  k8sapi-gateway reference Secret platform-mesh-system/domain-certificate — the self-signed leaf.
- There is NO Traefik default-certificate configured (no defaultCertificate arg, no providers.file/ConfigMap,
  no traefik.io TLSStore named "default"). So Traefik's served cert per host = the listener certRef.
- CRITICAL PROVENANCE: k8sapi-gateway is NOT a hand-authored object — it is TEMPLATED by Helm release
  "infra" (chart infra@0.34.0). infra .spec.values.gatewayApi.listeners[*].tls.certificateRefs and
  .listenersExtra[*] all hard-code name: domain-certificate. Flux (HelmRelease interval 1m) reconciles the
  Gateway back to those values. THAT is why the prior Phase-2 runtime patch of
  terminate-wildstar.certificateRefs (domain-certificate -> cert-p1) did NOT stick / did not change the
  served cert: even though the listener briefly showed Accepted/Programmed, Flux owns the Gateway and the
  authoritative desired-state still says domain-certificate. A runtime `kubectl patch` of the Gateway is
  reconciled away by the "infra" HelmRelease.
  => A DURABLE fix must change infra's Helm VALUES (gatewayApi.listeners[*].tls.certificateRefs.name ->
     cert-p1, incl listenersExtra + the aitrust listeners), NOT a runtime Gateway patch. Alternatively,
     make secret "domain-certificate" itself carry the LE material (but it is a static hand-applied
     kubernetes.io/tls secret with no gardener Certificate ownerRef — see prior backup-dnscert README).
  (This paragraph is analysis of the captured artifacts; NO change was made. It informs the GOAL, and the
   restore steps below return to the self-signed baseline regardless.)


====================================================================
HOW TO ROLL BACK to today's WORKING self-signed setup
====================================================================
Prereq — valid garden login, then a shoot admin kubeconfig:
  cd /mnt/c/claude/projects/eu-ai-trust-platform/Standard_AiTrust_MSP
  # if login expired:  bash prerequisites/login.sh
  # lib.sh's `sk` mints .state/shoot-kubeconfig.yaml automatically, or reuse an existing one:
  export KUBECONFIG=.state/shoot-kubeconfig.yaml
  BK=.state/backup-traefik

1) Restore the served TLS secret (the self-signed material). Apply this FIRST so listeners resolve:
     kubectl apply -f "$BK/secrets.yaml"
   NOTE: secrets.yaml contains BOTH domain-certificate AND cert-p1. cert-p1 is unchanged in the working
   baseline; re-applying it is harmless. If you only want to restore the self-signed secret, split the
   file and apply just the domain-certificate document.

2) Restore the Gateway listener certRefs (all terminate listeners -> domain-certificate):
     kubectl apply -f "$BK/gateway.yaml"
   ***Helm/Flux-managed*** — k8sapi-gateway is owned by HelmRelease platform-mesh-system/infra.
   A hand `apply` restores desired state immediately AND Flux will also re-assert infra's values
   (which already say domain-certificate) within ~1m, so this rollback is self-healing. HOWEVER, if a
   later DURABLE change edited infra's Helm VALUES to point at cert-p1, `kubectl apply -f gateway.yaml`
   is NOT enough — you MUST also revert the infra HelmRelease values (see step 4).

3) Restore the traefik data-plane objects only if a later change touched them (normally untouched):
     kubectl apply -f "$BK/traefik-deploy.yaml"      # deployment default/traefik
     kubectl apply -f "$BK/traefik-svc.yaml"         # LB Service (+ gardener DNS annotations)
     kubectl apply -f "$BK/traefik-crs.yaml"         # only the Middleware cors-header (the sole CR)
   ***Helm/Flux-managed*** — deploy+svc are owned by HelmRelease platform-mesh-system/traefik
   (release name "traefik" in ns default). Same caveat as the Gateway: if a durable change edited the
   traefik HelmRelease values, revert those too (step 4).

4) DURABLE revert (only if a change was made at the Helm layer):
   The authoritative desired-state lives in two Flux HelmReleases in ns platform-mesh-system:
     - infra    (chart infra@0.34.0,  OCIRepository infra)     -> owns k8sapi-gateway + cors-header Middleware
     - traefik  (chart traefik@39.0.7, OCIRepository traefik)  -> owns deploy/svc default/traefik
   To return them to today's state, restore their .spec.values to what this backup shows
   (traefik-helm-provenance.txt contains the FULL current YAML of both HelmReleases — the working values):
     kubectl -n platform-mesh-system apply -f <hand-extracted infra HelmRelease from provenance>
     kubectl -n platform-mesh-system apply -f <hand-extracted traefik HelmRelease from provenance>
   Then let Flux reconcile (interval 1m) or nudge with an annotation. Because the captured infra values
   already hard-code certificateRefs.name=domain-certificate on every listener, restoring them re-serves
   the self-signed cert everywhere. (Extract the two HelmRelease docs from traefik-helm-provenance.txt;
   they are reproduced there verbatim including .spec.values.)

Sanity checks after rollback (all READ-ONLY):
  kubectl -n platform-mesh-system get gateway k8sapi-gateway \
    -o jsonpath='{range .spec.listeners[*]}{.name}={.tls.certificateRefs[0].name}{"\n"}{end}'
  # expect every terminate* listener = domain-certificate
  echo | openssl s_client -connect 130.214.18.166:443 \
    -servername my-aitrust.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu 2>/dev/null \
    | openssl x509 -noout -subject -issuer
  # expect subject CN=ai-trust-1-mesh / issuer CN=Standard Platform Mesh Local CA (self-signed)


====================================================================
WHICH OBJECTS ARE FLUX/HELM-MANAGED (summary)
====================================================================
FLUX/HELM-MANAGED (a live revert may need a HelmRelease revert too — see step 4):
  - Gateway platform-mesh-system/k8sapi-gateway ............ HelmRelease "infra"    (ns platform-mesh-system)
  - Middleware platform-mesh-system/cors-header ............ HelmRelease "infra"
  - Deployment default/traefik ............................. HelmRelease "traefik"  (release ns default)
  - Service    default/traefik ............................. HelmRelease "traefik"
  - traefik CRDs ........................................... HelmRelease "traefik-crds"
STATIC / hand-applied (NOT owned by a gardener Certificate — see prior backup-dnscert README):
  - Secret platform-mesh-system/domain-certificate (self-signed material actually served)
GARDENER/cert-manager MANAGED (real LE material, target of the GOAL):
  - Secret platform-mesh-system/cert-p1 (issued by the gardener/LE Certificate cert-p1; renews ~Nov 2026)

suffix = ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu
