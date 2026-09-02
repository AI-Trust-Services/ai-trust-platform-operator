package main

import (
	"context"
	"fmt"
	"strings"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

type reconciler struct {
	client.Client               // LOCAL: prod kcp — Subscription watch, status, finalizer, dup guard.
	remote        client.Client // REMOTE: ai-trust-1 — all provisioning applies/reads + teardown.
	cfg           config
}

func (r *reconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	l := log.FromContext(ctx)
	cr := &unstructured.Unstructured{}
	cr.SetGroupVersionKind(gvk)
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	spec, _, _ := unstructured.NestedMap(cr.Object, "spec")
	display := strOr(spec["displayName"], "AI Trust Platform")
	adminEmail := strOr(spec["adminEmail"], "")
	// suspended (provider action): when true the tenant's oauth2-proxy is stamped with 0 replicas, so
	// its host stops serving (login blocked) while ALL data + resources stay intact. Reversible.
	suspended, _, _ := unstructured.NestedBool(cr.Object, "spec", "suspended")
	proxyReplicas := "1"
	if suspended {
		proxyReplicas = "0"
	}

	// org == the mesh account/realm. spec.org is authoritative. Trim whitespace BEFORE dnsSafe (dnsSafe
	// turns an internal space into '-', which would corrupt the realm name). No cluster-id fallback: an
	// empty org can only Degrade.
	//
	// FEDERATION: every federated tenant is namespaced with the `fed-` prefix on ai-trust-1 so it can
	// never collide with a1's native tenants (fridaytest/martin/…) or a same-named prod-local tenant.
	// This one substitution flows through EVERYTHING derived from org: the a1 Keycloak realm `fed-<org>`
	// (Stage 4 brokers prod's real `<org>` realm INTO it for SSO), the host ai-trust-fed-<org>.<a1-suffix>,
	// the PG schema tenant_fed_<org>, CH db tenant_fed_<org>, bucket tenant-fed-<org>, role t_fed_<org>,
	// and the oauth2-proxy/secret/route names.
	rawOrg := strings.TrimSpace(strOr(spec["org"], ""))
	baseOrg := dnsSafe(rawOrg)
	org := ""
	if baseOrg != "" {
		org = fedPrefix + baseOrg
	}
	tenantID := org
	orgHost := "ai-trust-" + org + "." + r.cfg.domainSuffix
	url := "https://" + orgHost

	// ---- finalizer / delete ----------------------------------------------------
	if !cr.GetDeletionTimestamp().IsZero() {
		if hasFinalizer(cr) {
			l.Info("de-provisioning subscription (soft-disable)", "org", org)
			r.deleteOrgResources(ctx, org)
			removeFinalizer(cr)
			_ = r.Update(ctx, cr)
		}
		return ctrl.Result{}, nil
	}
	if !hasFinalizer(cr) {
		addFinalizer(cr)
		if err := r.Update(ctx, cr); err != nil {
			return ctrl.Result{RequeueAfter: 5 * time.Second}, nil
		}
	}

	if rawOrg == "" {
		r.setPhase(ctx, cr, "Degraded", false, url, tenantID, org,
			"spec.org is empty — set it to the consumer org / mesh realm name so auth can be wired")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// ---- GUARD: one subscription per organization. The tenant host/URL and realm are BOTH derived
	//      from org (orgHost above), so two Subscriptions naming the same org would collide on the same
	//      host + tenant data. Policy is one-tenant-per-org, so a duplicate is rejected here (fail-closed,
	//      stamp nothing) rather than clobbering the existing tenant. Deterministic owner = the OLDEST
	//      active (non-deleting) Subscription for that org (by creationTimestamp, uid tie-break), so the
	//      choice is stable across restarts/re-reconciles and a Ready sub never Degrades itself.
	if owner := r.orgOwner(ctx, org, cr); owner != nil {
		ons, _, _ := unstructured.NestedString(owner.Object, "metadata", "namespace")
		oname, _, _ := unstructured.NestedString(owner.Object, "metadata", "name")
		l.Info("duplicate org — another subscription already owns this org; refusing to provision",
			"org", org, "owner", ons+"/"+oname)
		r.setPhase(ctx, cr, "Degraded", false, url, tenantID, org,
			fmt.Sprintf("Only one subscription is allowed per organization. Org '%s' already has an active "+
				"subscription ('%s/%s' at %s). Use the existing subscription, or delete it before creating a new one.",
				org, ons, oname, url))
		return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
	}

	// ---- 0. REALM — mode-dependent -----------------------------------------------------------------
	if r.cfg.federated {
		// FEDERATED: the payload realm `fed-<org>` doesn't exist until we make it. Stamp a Job ON THE
		// PAYLOAD cluster that (a) creates realm `fed-<org>`, (b) registers an OIDC IdP brokering the
		// Central `<baseOrg>` realm (Option A SSO), (c) adds a tenant_id mapper. The Job's SUCCESS is the
		// realm-exists proof — we do NOT re-check by HTTP, because the payload mesh Keycloak is only
		// reachable by in-cluster DNS FROM the payload (the Job's context), not from the Central controller.
		if err := r.ensureMeshAdminSecret(ctx); err != nil {
			return r.fail(ctx, cr, url, tenantID, org, "ensure mesh admin secret (broker)", err)
		}
		brokerSecret := "aitrust-fedbroker-" + org
		if _, _, err := r.ensureOrgSecret(ctx, brokerSecret, org); err != nil {
			return r.fail(ctx, cr, url, tenantID, org, "ensure broker client secret", err)
		}
		brokerJob := dnsSafe("kc-broker-" + org)
		if !r.jobExists(ctx, r.cfg.providerNS, brokerJob) {
			doc, err := r.render("keycloak-broker-job.tmpl", map[string]string{
				"__JOB_NAME__": brokerJob, "__NS__": r.cfg.providerNS, "__ORG__": org, "__BASEORG__": baseOrg,
				"__POOL_LABEL__": r.cfg.poolLabel, "__KC_INTERNAL__": r.cfg.kcInternal,
				"__PROD_KC_PUBLIC__": r.cfg.prodKcPublic, "__PROD_CLIENT_ID__": r.cfg.idpClientID,
				"__SECRET_NAME__": brokerSecret, "__SECRET_KEY__": "client-secret",
			})
			if err != nil {
				return r.fail(ctx, cr, url, tenantID, org, "render kc-broker job", err)
			}
			if err := r.applyDoc(ctx, doc); err != nil {
				return r.fail(ctx, cr, url, tenantID, org, "stamp kc-broker job", err)
			}
		}
		if !r.jobSucceeded(ctx, r.cfg.providerNS, brokerJob) {
			l.Info("waiting for payload realm+IdP broker Job", "org", org, "realm", org)
			r.setPhase(ctx, cr, "Provisioning", false, url, tenantID, org,
				fmt.Sprintf("creating payload realm '%s' + brokering Central realm '%s' (SSO) — not ready yet", org, baseOrg))
			return ctrl.Result{RequeueAfter: 15 * time.Second}, nil
		}
		l.Info("payload realm+IdP broker Job succeeded — realm ready, proceeding", "org", org, "brokers", baseOrg)
	} else {
		// LOCAL (single-cluster): the mesh Keycloak realm named <org> MUST already exist before we stamp any
		// auth resources (a phantom org would otherwise get a login proxy pointing at a missing realm). The
		// mesh Keycloak is in-cluster and reachable, so we verify directly. Fail-closed on an inconclusive
		// check. (This is the stock single-cluster realm gate.)
		adminUser, adminPass, err := r.readMeshAdminCreds(ctx)
		if err != nil {
			return r.fail(ctx, cr, url, tenantID, org, "read mesh admin creds for realm check", err)
		}
		tok, err := kcAdminToken(ctx, r.cfg.kcInternal, adminUser, adminPass)
		if err != nil {
			l.Info("realm check: admin token failed — not provisioning, will retry", "org", org, "err", err.Error())
			r.setPhase(ctx, cr, "Degraded", false, url, tenantID, org,
				fmt.Sprintf("could not verify Keycloak realm '%s' in the mesh (transient) — retrying", org))
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		switch checkRealmExists(ctx, r.cfg.kcInternal, tok, org) {
		case realmMissing:
			l.Info("org has no mesh Keycloak realm — refusing to provision (no login proxy stamped)", "org", org)
			r.setPhase(ctx, cr, "Degraded", false, url, tenantID, org,
				fmt.Sprintf("org '%s' has no Keycloak realm in the mesh — onboard the org first, or fix spec.org", org))
			return ctrl.Result{RequeueAfter: 2 * time.Minute}, nil
		case realmUnknown:
			l.Info("realm existence check inconclusive — not provisioning, will retry", "org", org)
			r.setPhase(ctx, cr, "Degraded", false, url, tenantID, org,
				fmt.Sprintf("could not verify Keycloak realm '%s' in the mesh (transient) — retrying", org))
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		case realmExists:
			// fall through to provisioning
		}
	}

	// ---- 0b. PER-TENANT STORES (physical isolation across Postgres + ClickHouse + MinIO) --------
	// Provision the tenant's own Postgres schema `tenant_<org>`, ClickHouse database `tenant_<org>`,
	// and MinIO bucket `tenant-<org>` (hyphens→underscores for PG/CH identifiers; hyphens for the S3
	// bucket) via ONE Job (CH+MinIO as init containers, PG as the main container). GATE Ready on the
	// Job succeeding, so the tenant host is never advertised before its stores exist (fail-closed:
	// the Subscription sits in Provisioning until then). Idempotent throughout.
	//
	// DURABLE provisioned-marker (same rationale as the stock operator): the tenant-stores Job on the
	// PAYLOAD cluster carries ttlSecondsAfterFinished and is deleted ~15 min after it completes. Without a
	// durable record the controller would re-stamp it and the re-run would fail on an already-provisioned
	// tenant → the (local, Central) Subscription would flip back to Provisioning forever. So once the Job
	// has succeeded we stamp an annotation on the local Subscription and never re-stamp thereafter.
	storesDoneAnn := gvk.Group + "/stores-provisioned"
	schemaName := "tenant_" + strings.ReplaceAll(org, "-", "_")
	bucketName := "tenant-" + strings.ToLower(strings.ReplaceAll(org, "_", "-"))
	storesJob := dnsSafe("tenant-stores-" + org)
	if cr.GetAnnotations()[storesDoneAnn] != "true" {
		if !r.jobExists(ctx, r.cfg.providerNS, storesJob) {
			doc, err := r.render("tenant-stores-job.tmpl", map[string]string{
				"__JOB_NAME__": storesJob, "__NS__": r.cfg.providerNS, "__ORG__": org,
				"__SCHEMA__": schemaName, "__POOL_LABEL__": r.cfg.poolLabel,
				"__DBMIGRATE_IMAGE__": r.cfg.dbMigrateImage, "__APP_ROLE__": r.cfg.appRole,
				"__CHMIGRATE_IMAGE__": r.cfg.chMigrateImage, "__CH_DB__": schemaName, "__BUCKET__": bucketName,
			})
			if err != nil {
				return r.fail(ctx, cr, url, tenantID, org, "render tenant-stores job", err)
			}
			if err := r.applyDoc(ctx, doc); err != nil {
				return r.fail(ctx, cr, url, tenantID, org, "stamp tenant-stores job", err)
			}
		}
		if !r.jobSucceeded(ctx, r.cfg.providerNS, storesJob) {
			l.Info("waiting for per-tenant Postgres schema provisioning", "org", org, "schema", schemaName)
			r.setPhase(ctx, cr, "Provisioning", false, url, tenantID, org,
				fmt.Sprintf("provisioning tenant store (Postgres schema '%s') — not ready yet", schemaName))
			return ctrl.Result{RequeueAfter: 15 * time.Second}, nil
		}
		if err := r.markProvisioned(ctx, cr, storesDoneAnn); err != nil {
			l.Info("could not set stores-provisioned annotation (will retry)", "org", org, "err", err.Error())
			return ctrl.Result{RequeueAfter: 5 * time.Second}, nil
		}
	}

	// ---- 1. per-org secret (client secret + cookie secret) ---------------------
	secretName := "aitrust-oauth2-" + org
	clientSecret, cookieSecret, err := r.ensureOrgSecret(ctx, secretName, org)
	if err != nil {
		return r.fail(ctx, cr, url, tenantID, org, "ensure secret", err)
	}
	_ = clientSecret // consumed by the Job + proxy via secretKeyRef

	// ---- 2. per-org OIDC client in the mesh realm (idempotent Job) -------------
	// The Job authenticates to the MESH Keycloak, so it needs the mesh bootstrap-admin creds. Copy that
	// secret from the mesh ns into the provider ns once (fresh deploys get it automatically — no manual step).
	if err := r.ensureMeshAdminSecret(ctx); err != nil {
		return r.fail(ctx, cr, url, tenantID, org, "ensure mesh admin secret", err)
	}
	jobName := dnsSafe("kc-client-" + org)
	if !r.jobExists(ctx, r.cfg.providerNS, jobName) {
		doc, err := r.render("keycloak-client-job.tmpl", map[string]string{
			"__JOB_NAME__": jobName, "__NS__": r.cfg.providerNS, "__ORG__": org,
			"__POOL_LABEL__": r.cfg.poolLabel, "__KC_INTERNAL__": r.cfg.kcInternal,
			"__CB_URL__": url + "/oauth2/callback", "__ORIGIN__": url,
			"__CLIENT_ID__": "aitrust-app", "__SECRET_NAME__": secretName, "__SECRET_KEY__": "client-secret",
		})
		if err != nil {
			return r.fail(ctx, cr, url, tenantID, org, "render kc-client job", err)
		}
		if err := r.applyDoc(ctx, doc); err != nil {
			return r.fail(ctx, cr, url, tenantID, org, "stamp kc-client job", err)
		}
	}

	// ---- 3. per-org oauth2-proxy + Service + HTTPRoute + ReferenceGrant --------
	proxyDoc, err := r.render("oauth2-proxy-org.tmpl", map[string]string{
		"__ORG__": org, "__NS__": r.cfg.providerNS, "__ORG_HOST__": orgHost,
		"__KC_INTERNAL_REALM__": r.cfg.kcInternal + "/realms/" + org,
		"__KC_PUBLIC_REALM__":   r.cfg.kcPublic + "/realms/" + org,
		"__WHITELIST_DOMAIN__":  r.cfg.domainSuffix,
		"__SECRET_NAME__":       secretName, "__SECRET_KEY__": "client-secret",
		"__COOKIE_SECRET__": cookieSecret, "__REPLICAS__": proxyReplicas,
		"__GATEWAY_NS__":    r.cfg.gatewayNS, "__GATEWAY_NAME__": r.cfg.gatewayName,
		"__GATEWAY_SECTION__": r.cfg.gatewaySection,
	})
	if err != nil {
		return r.fail(ctx, cr, url, tenantID, org, "render oauth2-proxy", err)
	}
	if err := r.applyDoc(ctx, proxyDoc); err != nil {
		return r.fail(ctx, cr, url, tenantID, org, "stamp oauth2-proxy", err)
	}

	// ---- 4. seed the org admin's role tuple in the SHARED store (best-effort) --
	if adminEmail != "" && r.cfg.storeID != "" {
		if err := r.seedAdminTuple(ctx, adminEmail); err != nil {
			l.Info("admin tuple seed failed (non-fatal)", "err", err.Error())
		}
	}

	// ---- 4b. RECIPROCAL SSO CLIENT (federated only) — register the OIDC client in the CENTRAL realm
	//      <baseOrg> that the payload's `prod` IdP uses, so the browser SSO round-trip completes. Runs as a
	//      Job on the CENTRAL cluster (local to this controller), because the Central mesh Keycloak is
	//      reachable here. Uses the SAME per-org secret the payload IdP holds. BEST-EFFORT + non-fatal.
	//      Skipped entirely in local mode (no cross-Keycloak brokering there).
	if r.cfg.federated {
		if err := r.reconcileReciprocalSSO(ctx, l, org, baseOrg); err != nil {
			l.Info("reciprocal Central-side SSO client not wired yet (non-fatal)", "org", org, "baseOrg", baseOrg, "reason", err.Error())
		}
	}

	// ---- 5. status -------------------------------------------------------------
	if suspended {
		r.setPhase(ctx, cr, "Suspended", false, url, tenantID, org,
			fmt.Sprintf("tenant '%s' SUSPENDED by provider: login blocked (oauth2-proxy scaled to 0); data + stores intact. Resume to restore.", tenantID))
		_ = display
		return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
	}
	readyMsg := fmt.Sprintf("tenant '%s' active: mesh realm '%s' + per-org oauth2-proxy at %s (physical schema/DB/bucket isolation)", tenantID, org, orgHost)
	if r.cfg.federated {
		readyMsg = fmt.Sprintf("federated tenant '%s' active ON the payload cluster: realm '%s' (brokers Central '%s' for SSO) + per-org oauth2-proxy at %s (physical schema/DB/bucket isolation)", tenantID, org, baseOrg, orgHost)
	}
	r.setPhase(ctx, cr, "Ready", true, url, tenantID, org, readyMsg)
	_ = display
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}
